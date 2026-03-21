# Architektura — griluju-yt-pipeline

## Stack

| Komponenta | Technologie | Verze |
|---|---|---|
| Webová aplikace | Ruby on Rails | 8.x |
| Databáze | PostgreSQL | 16+ |
| Background joby | Sidekiq | 7.x |
| Message broker | Redis | 7.x |
| YouTube scraping | yt-dlp | **fixovat v Dockerfilu** — aktuálně `2026.03.17` |
| JS runtime (yt-dlp dep) | Deno | povinné od ~2025 |
| Speech-to-text | whisper-ctranslate2 | 0.4.4 (zkontroluj aktuální verzi) |
| Kontejnerizace | Docker Compose | — |

---

## Docker Compose

Celý stack běží v kontejnerech — výhoda: stejná konfigurace lokálně (OrbStack VM) i na produkci (Hetzner).

```
services:
  web       — Rails app (Puma)
  worker    — Sidekiq
  db        — PostgreSQL
  redis     — Redis
```

**Whisper model:** pre-stažen do image při build time (`/opt/whisper_models`) — model `medium` (~1.5 GB). Bez volume → model přežije restart kontejneru. Viz Dockerfile sekce whisper.

**yt-dlp verze:** fixovat v Dockerfilu (`pip install yt-dlp==2026.03.17`). YouTube občas mění API — fixovaná verze zajistí vědomou aktualizaci.

**Deno:** povinná závislost yt-dlp od ~2025 pro řešení YouTube JavaScript výzev. Musí být nainstalován v Docker image.

---

## Modely

### YoutubeChannel
```
name              string
channel_id        string, unique
channel_url       string
active            boolean, default true
tags              jsonb, default '[]'
last_checked_at   datetime
default_language  string, default 'en'
backfill_limit    integer, default 30
```

### YoutubeVideo
```
youtube_video_id   string, unique
youtube_channel    belongs_to
title              string
description        text
video_url          string
thumbnail_url      string
published_at       datetime
duration_seconds   integer, nullable
processing_status  string  — viz stavový automat níže
failed_reason      text
retry_count        integer, default 0
webhook_sent_at    datetime, nullable
queued_for_blog    boolean, default false
```

### VideoTranscript
```
youtube_video             belongs_to
source_type               string  — 'manual_subtitles' | 'whisper_local' | 'auto_captions_youtube'
raw_transcript            text
cleaned_transcript        text
language                  string
available                 boolean
word_count                integer  — plní se automaticky (before_save)
transcript_quality_score  integer  — manual=3, whisper=2, auto=1 (before_save)
captions_source_detail    string
```

---

## Stavový automat

```
new → metadata_fetched → transcript_ready
        ↘ failed            ↘ failed
        ↘ skipped
```

| Stav | Popis |
|---|---|
| `new` | Video detekováno z RSS |
| `metadata_fetched` | yt-dlp metadata stažena, není Shorts/live |
| `transcript_ready` | Přepis vyčištěn a uložen |
| `failed` | Zpracování selhalo (viz `failed_reason`) |
| `skipped` | Záměrně přeskočeno — Shorts, live přenos |

`skipped` je konečný stav, **ne chyba**.

Důvody `skipped`:
- `live_content` — živý přenos, premiéra, replay
- `short_video` — URL `/shorts/` nebo délka < 120s

---

## Jobs a pipeline flow

### ProcessVideoJob
1. Stáhne metadata (`yt-dlp --dump-json --skip-download`)
2. Uloží `duration_seconds`
3. Zkontroluje Shorts/live → `skipped` nebo pokračuje
4. Přechod na `metadata_fetched` → enqueue `FetchTranscriptJob`

### FetchTranscriptJob
Priorita titulků:
1. Manuální titulky (`--write-subs --sub-lang en,en-US,en-GB`)
2. Whisper local (`whisper-ctranslate2`) — pro videa bez manuálních titulků
3. YouTube auto-captions (`--write-auto-subs`) — záchrana pokud Whisper selže

Po úspěchu → `VttCleaner.call` → uložení `VideoTranscript` → `transcript_ready` → enqueue `NotifyBlogJob`

### NotifyBlogJob
POST na `BLOG_WEBHOOK_URL` s HMAC-SHA256 signaturou. Po úspěchu → `webhook_sent_at = Time.current`.

---

## Sidekiq konfigurace

```yaml
# config/sidekiq.yml
:queues:
  - default
  - yt_dlp      # max 3 concurrent (rate limit YouTube)
  - whisper     # max 1 concurrent (OOM prevence)
```

**Retry strategie:** 3 pokusy s custom backoffem:
- 1. retry: 5 minut
- 2. retry: 15 minut
- 3. retry: 45 minut

Každý job má `rescue StandardError` → `video.increment!(:retry_count)` → `raise` (Sidekiq musí chybu dostat).

---

## Services

| Service | Zodpovědnost |
|---|---|
| `Youtube::RssPollerService` | Polling RSS feedů, detekce nových videí |
| `Youtube::VideoMetadataService` | Volání yt-dlp --dump-json |
| `Youtube::TranscriptService` | Orchestrace stahování titulků / Whisper |
| `Blog::VttCleanerService` | Strip VTT tagů + sliding-window deduplikace rolling captions |
| `Blog::WebhookService` | HMAC-SHA256 podpis + POST notifikace blogu |

**Shell injection prevence:** vždy `Open3.capture3(příkaz, arg1, arg2, ...)` s polem argumentů, nikdy string interpolace.

**Dočasné soubory:** vždy `ensure FileUtils.rm_f(path) if path && File.exist?(path)` — platí pro audio MP3 i VTT soubory.

---

## API

Autentizace: `X-Api-Key` hlavička (statický secret, sdílený s blogem).

```
GET  /api/v1/transcripts/:video_id
     → { video_id, title, channel, published_at, language, cleaned_transcript, source_type }

GET  /api/v1/videos?status=transcript_ready&webhook_sent_at=null
     → videa čekající na webhook notifikaci

GET  /api/v1/videos?queued_for_blog=true
     → videa manuálně označená ke zpracování

PATCH /api/v1/videos/:video_id
     → { queued_for_blog: true }
```

---

## Databázové indexy

```ruby
# Povinné — bez těchto indexů jsou API dotazy full table scan
add_index :youtube_videos, :processing_status
add_index :youtube_videos, :webhook_sent_at
add_index :youtube_videos, :queued_for_blog
add_index :youtube_videos, [:processing_status, :webhook_sent_at]  # nejčastější dotaz
add_index :youtube_videos, [:processing_status, :updated_at]       # recover_stuck_videos
```

---

## Rake tasks

```bash
rails pipeline:retry_failed              # Re-queue failed videí
rails pipeline:retry_failed CHANNEL=UC.. # Filtrování per kanál
rails channels:resolve_id URL=https://youtube.com/@Handle  # Zjistí channel_id z URL
```

---

## ENV proměnné

```
DATABASE_URL
REDIS_URL
BLOG_WEBHOOK_URL     # URL blogu pro POST notifikace
BLOG_WEBHOOK_SECRET  # HMAC klíč — nikdy neposílat v hlavičce
BLOG_API_KEY         # API klíč pro X-Api-Key hlavičku
APP_URL              # Base URL pipeline (pro transcript_url v payloadu)
```

---

## Infrastruktura

**Lokálně (vývojová fáze):** OrbStack VM `griluju-yt` — Docker Compose, model Whisper `medium` (`small` pro vývoj pokud RAM nestačí).

**Produkce (výhledově):** Hetzner CX32 (4 vCPU, 8 GB RAM) — minimum pro Whisper `medium`. CX22 (4 GB) nestačí — OOM kill při Whisper jobu.

---

## Agent workflow

Viz `.claude/commands/` pro dostupné skills:
- `/review` — pre-commit kontroly
- `/session-end` — uzavření sezení
- `/systematic-debugging` — debugovací protokol
