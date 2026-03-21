# Zadání: automatický monitoring YouTube kanálů a zpracování videí pro blog o grilování
<!-- v13 — opravy z code review: pipeline diagram měl starý Shorts guard (< 90s → < 120s + URL guard na první místo), Whisper volání doplněna o --output_format vtt a --output_dir (bez toho generoval více souborů do CWD), ensure blok transcribe_with_whisper doplněn o cleanup Whisper VTT výstupu, přidán composite index [:processing_status, :updated_at] pro recover_stuck_videos query, recover_stuck_videos filtruje podle channel.active (deaktivované kanály se nebudou re-enqueue donekonečna), přidáno upozornění na ověření verze whisper-ctranslate2 před nasazením -->
<!-- v11 — opravy z code review: faster-whisper --model_dir flag (fix OOM bug), VTT temp file cleanup (ensure blok), find_or_create_by! rescue ActiveRecord::RecordNotUnique, Sidekiq custom backoff implementace (sidekiq_retry_in), idempotence guard v ProcessVideoJob, language field v GET /api/v1/transcripts response -->

## Cíl projektu

Interní nástroj pro blog o grilování, který automaticky sleduje vybrané zahraniční YouTube kanály, detekuje nově publikovaná videa, získává z nich přepis, čistí ho a ukládá do databáze. Zpracování obsahu (analýza, psaní článku, tone of voice) probíhá na straně blogu — pipeline je čistě sběrný a přípravný nástroj.

---

## Kontext

Blog o grilování sleduje zahraniční YouTube kanály zaměřené na:

- grilování masa a BBQ techniky
- recepty a postupy přípravy
- testování grilů a vybavení
- tipy, triky, marinády, rubs, sauces
- kouření masa / smoking

---

## Hlavní požadavek

MVP systém který umí:

1. Sledovat seznam YouTube kanálů přes RSS
2. Rozpoznat nově publikované video
3. Uložit metadata videa
4. Získat přepis / titulky přes yt-dlp
5. Přepis vyčistit a strukturovat
6. Uložit výstup do databáze
7. Notifikovat blog přes webhook (přepis je připraven ke zpracování)
8. Umožnit pozdější rozšíření

> **Poznámka k architektuře:** Pipeline nedělá žádnou AI analýzu — ta probíhá výhradně na blogu, kde jsou nastavená pravidla pro tone of voice, strukturu článků a další redakční parametry. Pipeline je sběrač a přípravář surových dat.

---

## Stack

- **Ruby on Rails** (hlavní aplikace)
- **PostgreSQL** (databáze)
- **Sidekiq** (background joby)
- **yt-dlp** (CLI nástroj — metadata, titulky) — verze fixovaná v Dockeru
- **Docker** — lokální vývoj i produkční server

---

## Klíčová architektonická rozhodnutí

### yt-dlp jako jediný nástroj pro YouTube

yt-dlp nahrazuje všechny ostatní závislosti:

| Potřeba | Řešení |
|---|---|
| Metadata videa | `yt-dlp --dump-json --skip-download` |
| Manuální titulky | `yt-dlp --write-subs --sub-lang "en,en-US,en-GB" --skip-download` |
| Auto-generované titulky | `yt-dlp --write-auto-subs --sub-lang "en,en-US,en-GB" --skip-download` |
| Audio pro speech-to-text | `yt-dlp -x --audio-format mp3` (post-MVP) |

Výhody: žádný YouTube Data API klíč, žádné kvóty, jeden nástroj pro vše, aktivně udržovaný projekt.

**Rate limiting:** yt-dlp joby nespouštět paralelně více než 3 najednou (Sidekiq concurrency limit pro frontu `yt_dlp`). Předejde blokování ze strany YouTube.

**Backfill nových kanálů:** Při přidání nového kanálu se automaticky zpracuje posledních 30 videí zpětně. Řazení podle views/liků není praktické (vyžadovalo by stáhnout metadata všech videí kanálu). Používáme chronologický backfill přes `--playlist-end`:

```bash
yt-dlp --playlist-end 30 --dump-json --skip-download \
  "https://www.youtube.com/@ChannelHandle"
```

`backfill_limit` je konfigurovatelný per kanál (default 30). Nový kanál s méně videi automaticky zpracuje jen ta dostupná.

**Verze yt-dlp:** fixovat konkrétní verzi v Dockerfilu (`pip install yt-dlp==VERZE`). YouTube občas mění API a nová verze yt-dlp je nutná — fixovaná verze zajistí, že víš kdy a proč přestalo fungovat, a můžeš verzi vědomě aktualizovat.

> **⚠️ Aktuální stabilní verze: `2026.03.17`** (původní plán měl `2024.12.23` — 15 měsíců stará verze, která s vysokou pravděpodobností aktuálně nefunguje pro YouTube).

**JavaScript runtime — nová povinná závislost (od ~2025):** yt-dlp nově vyžaduje externí JS runtime pro řešení YouTube JavaScript výzev. Doporučený runtime je **Deno** — musí být nainstalován v Dockeru vedle yt-dlp. Bez Dena yt-dlp YouTube nepodporuje vůbec (`yt-dlp-ejs` package je také nutný). Viz [dokumentace](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-install-or-use-an-external-javascript-runtime).

### RSS Atom feed pro detekci videí

Každý YouTube kanál má veřejný RSS feed:
```
https://www.youtube.com/feeds/videos.xml?channel_id=CHANNEL_ID
```
Funguje bez API klíče, bez kvót, spolehlivě.

### Webhook pro notifikaci blogu

Po úspěšném uložení přepisu pipeline pingne blog POST requestem s `video_id`. Blog si přepis stáhne a spustí vlastní AI zpracování. Tím odpadá potřeba ručního kopírování dat.

---

## Funkční požadavky

### 1. Správa sledovaných kanálů

**Zjištění `channel_id` z URL kanálu:** Lidé znají URL nebo handle kanálu, ne interní ID. Přidej helper do rake tasku nebo admin UI:

```bash
# Zjistí channel_id z libovolného formátu URL
yt-dlp --print channel_id --skip-download "https://www.youtube.com/@BBQwithFranklin"
yt-dlp --print channel_id --skip-download "https://www.youtube.com/c/BBQwithFranklin"
# → UCxyz123...
```

```ruby
# rake task: rails channels:resolve_id URL=https://youtube.com/@BBQwithFranklin
task resolve_id: :environment do
  url = ENV['URL']
  require 'open3'
  # Open3 předává argumenty jako pole — neprojdou shellem, shell injection není možný
  stdout, _err, status = Open3.capture3(
    '/opt/pyenv/bin/yt-dlp', '--print', 'channel_id', '--skip-download', url
  )
  abort "yt-dlp selhalo" unless status.success?
  channel_id = stdout.strip
  puts "channel_id: #{channel_id}"
  puts "RSS feed:   https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}"
end
```

Model `YoutubeChannel`:

```
- name              (string)
- channel_id        (string, unikátní)
- channel_url       (string)
- active            (boolean, default true)
- tags              (jsonb, default '[]') — PostgreSQL jsonb místo string[]; flexibilnější pro dotazování (WHERE tags @> '["bbq"]'), snazší migrace schématu
- last_checked_at   (datetime)
- default_language  (string, default 'en') — očekávaný jazyk kanálu; předá se Whisperu jako hint
- backfill_limit    (integer, default 30)  — kolik videí zpětně zpracovat při přidání kanálu
```

**Detekce jazyka přepisu:** Jazyk se zjišťuje v tomto pořadí:
1. Z metadat yt-dlp (`automatic_captions` nebo `subtitles` klíče obsahují jazyk)
2. Z `default_language` kanálu jako fallback

Uložený jazyk na `VideoTranscript.language` slouží blogu pro správné zpracování — zejména pro rozlišení anglických a českých kanálů (český kanál nepotřebuje překlad, jen přepis).

```ruby
# services/youtube/transcript_service.rb
detected_language = subtitle_info&.dig('language') || channel.default_language
transcript.language = detected_language

# Předání jazyka Whisperu — příkaz whisper-ctranslate2 (CLI wrapper nad faster-whisper)
whisper-ctranslate2 audio.mp3 --model medium --model_dir /opt/whisper_models \
  --language #{detected_language} \
  --output_format vtt \
  --output_dir /tmp/whisper/ \
  --initial_prompt "BBQ, brisket, bark, stall, tallow injection, spritzing, smoke ring, \
Traeger, Kamado Joe, Weber, Big Green Egg, offset smoker, pellet grill, \
pulled pork, pork butt, pork shoulder, St. Louis ribs, spare ribs, baby back, \
dry rub, wet rub, marinade, brine, mop sauce, burnt ends, flat, point, \
internal temperature, probe tender, thermometer, Thermapen, Meater, \
Aaron Franklin, Malcom Reed, Mad Scientist BBQ, Chud's BBQ, kosher salt, coarse pepper"
```

### 2. Detekce nových videí

- Polling RSS feedů přes Sidekiq scheduled job (každých 6 hodin)
- Fallback: manuální trigger přes rake task nebo admin UI
- Deduplikace přes `youtube_video_id` (unique index)

**Timezone:** RSS feed vrací `published` v různých formátech (RFC 822, ISO 8601). Vždy parsuj přes `Time.parse(...).utc` a ukládej jako UTC — předejdeš edge casům při porovnávání s `last_checked_at`.

```ruby
# rss_poller.rb
published_at = Time.parse(entry.published).utc

# find_or_create_by! není na úrovni DB atomické — je to find + insert ve dvou krocích.
# Při souběhu dvou workerů oba projdou find (vrátí nil) a oba se pokusí o insert.
# Unique index duplikát zabrání, ale druhý worker vyhodí ActiveRecord::RecordNotUnique.
# rescue to zachytí čistě — video existuje, nic nedělej.
video = YoutubeVideo.find_or_create_by!(youtube_video_id: video_id) do |v|
  v.youtube_channel = channel
  v.title           = entry.title
  v.video_url       = entry.url
  v.published_at    = published_at
  v.processing_status = 'new'
end

ProcessVideoJob.perform_later(video.id) if video.previously_new_record?
next  # přeskočit zbytek bloku pro existující videa
rescue ActiveRecord::RecordNotUnique
  # Jiný worker vyhrál race condition — video existuje, přeskočit
  Rails.logger.info "[Pipeline] Race condition handled for #{video_id}"
  next
```

Model `YoutubeVideo`:

```
- youtube_video_id   (string, unikátní)
- youtube_channel    (belongs_to)
- title              (string)
- description        (text)
- video_url          (string)
- thumbnail_url      (string)
- published_at       (datetime)
- duration_seconds   (integer, nullable) — z yt-dlp metadata['duration']; plní ProcessVideoJob; nil = zatím neznámé
- processing_status  (string) — viz stavový automat
- failed_reason      (text)
- retry_count        (integer, default 0)
- webhook_sent_at    (datetime, nullable) — automaticky: kdy byl blog notifikován přes webhook; nil = notifikace ještě neproběhla
- queued_for_blog    (boolean, default false) — manuální příznak v admin UI: redaktor označí video k zpracování mimo automatický webhook flow
```

> **Poznámka k sémantice:** `webhook_sent_at` a `queued_for_blog` jsou záměrně oddělené fieldy s různou sémantikou. `webhook_sent_at` plní pipeline automaticky po úspěšné notifikaci — slouží pro API dotaz `?webhook_sent_at=null` (videa čekající na notifikaci). `queued_for_blog` je výhradně manuální příznak pro admin UI — redaktor jím označí video ke zpracování mimo automatický flow (např. starší video z backfillu). Tím se předchází situaci kdy API vrací videa notifikovaná webhookem jako "čekající".
>
> `language` field byl odstraněn z `YoutubeVideo` — jazyk je vlastnost přepisu, ne videa jako takového, a ukládá se na `VideoTranscript.language`. Pokud pipeline přepis ještě nezpracovala, jazyk není znám.

**Filtrování nevhodného obsahu — Shorts a živé přenosy:**

`ProcessVideoJob` zkontroluje metadata hned po stažení a přeskočí obsah, který pipeline nemá zpracovávat. Vše co není běžné nahrané video skončí ve stavu `skipped` — ne `failed`.

```ruby
# jobs/process_video_job.rb
def perform(video_id)
  video    = YoutubeVideo.find(video_id)

  # Idempotence guard — při re-queue (recovery, rake task) nesmí duplikovat zpracování
  return if video.transcript_ready? || video.skipped?

  metadata = VideoMetadataService.call(video)  # yt-dlp --dump-json

  video.update!(duration_seconds: metadata['duration'])

  if (skip_reason = skip_reason_for(metadata))
    video.update!(processing_status: 'skipped', failed_reason: skip_reason)
    Rails.logger.info "[Pipeline] Skipped #{video.youtube_video_id}: #{skip_reason}"
    return
  end

  video.update!(processing_status: 'metadata_fetched')
  FetchTranscriptJob.perform_later(video.id)
end

private

def skip_reason_for(metadata)
  # Přeskočit vše co není standardní nahrané video:
  # is_live (aktivní stream), is_upcoming (premiéra), post_live (replay), was_live (archiv streamu)
  return 'live_content' unless metadata['live_status'] == 'not_live'

  # Přeskočit Shorts — URL guard je primární (spolehlivý), duration je záchrana pro edge case
  # Hranice < 120s místo < 90s: YouTube Shorts mohou trvat přesně 90s nebo 91s a projít guardaem.
  # URL /shorts/ vždy preferuj — duration slouží jen jako pojistka pro Shorts bez správné URL.
  return 'short_video' if metadata['webpage_url'].to_s.include?('/shorts/')
  return 'short_video' if metadata['duration'].to_i < 120

  nil  # vše ok, zpracuj normálně
end
```

### 3. Získání přepisu — priorita a kvalita

BBQ obsah má specifické požadavky na kvalitu přepisu: oborová terminologie (bark, stall, tallow injection, spritzing), názvy brandů (Traeger, Kamado Joe, Weber) a regionální přízvuky (Texas, Jih USA, Austrálie). YouTube auto-captions na tento obsah nestačí — fonetické záměny (`brisket` → `bris kit`, `Kamado` → `Camato`) degradují přepis natolik, že AI na blogu z něj nemůže správně vyextrahovat recept ani tipy.

**Priorita titulků:**

1. **Manuální titulky** (`--write-subs`) — spolehlivé, používej vždy pokud dostupné
2. **Whisper local** (`whisper-ctranslate2`, běží v Dockeru) — pro videa bez manuálních titulků; zdarma, bez externích závislostí
3. **YouTube auto-captions** (`--write-auto-subs`) — pouze jako záchrana pokud Whisper selže

**Whisper setup v Dockeru:**

```dockerfile
# whisper-ctranslate2 — CLI wrapper nad faster-whisper, poskytuje příkaz whisper-ctranslate2 v shellu
# POZOR: faster-whisper samotný CLI nemá — `faster-whisper audio.mp3` selže s "command not found"
# ⚠️ Verze: zkontroluj aktuální stabilní release (`pip index versions whisper-ctranslate2`)
# před první instalací — 0.4.4 je reference z v12, novější verze může opravit kompatibilitu
# s aktuálním yt-dlp a Denem.
RUN pip install whisper-ctranslate2==0.4.4
```

> **⚠️ Whisper model cache — kritický detail pro produkci:**
> `whisper-ctranslate2` stahuje model při prvním použití do `~/.cache/huggingface/hub/`. V kontejneru tato cesta **nepřežije restart** pokud není namountovaný volume. Model `medium` = ~1,5 GB. První Whisper job po restartu kontejneru by stáhl 1,5 GB za provozu — timeout nebo OOM.
>
> **Dvě možnosti řešení:**

**Varianta A — pre-download do image (doporučeno pro produkci):**
Model je součástí Docker image. Větší image (~2 GB navíc), ale spolehlivé — po restartu kontejneru není žádné stahování.

```dockerfile
# Stáhne model medium při build time — uloží do /opt/whisper_models
# whisper-ctranslate2 interně používá faster-whisper → WhisperModel import funguje stejně
RUN python3.11 -c "from faster_whisper import WhisperModel; WhisperModel('medium', download_root='/opt/whisper_models')"
ENV WHISPER_MODEL_PATH=/opt/whisper_models
```

```ruby
# Volání Whisperu s explicitní cestou k modelu
# services/youtube/transcript_service.rb
# POZOR: --model přijímá název modelu, --model_dir přijímá adresář s pre-downloaded modelem
# Bez --model_dir by Whisper ignoroval /opt/whisper_models a stahoval model za provozu → OOM
whisper-ctranslate2 audio.mp3 --model medium --model_dir /opt/whisper_models \
  --language #{detected_language} \
  --output_format vtt \
  --output_dir /tmp/whisper/ \
  --initial_prompt "BBQ, brisket, bark, stall, ..."
```

**Varianta B — Docker volume (menší image, vyžaduje inicializaci):**
Model se stáhne při prvním spuštění a přežívá restarty kontejneru díky volume.

```yaml
# docker-compose.yml
volumes:
  whisper_cache: {}
services:
  worker:
    volumes:
      - whisper_cache:/root/.cache
```

> **Kdy použít co:** Pro Hetzner produkci doporučena Varianta A — předvídatelné build time, nulové překvapení po restartu serveru. Varianta B je vhodná pro lokální vývoj kde nechceš nafouknout image.

```bash
# Volání z Ruby přes system call, stejně jako yt-dlp
# --model_dir: adresář s pre-downloaded modelem (Varianta A z Dockerfilu)
# --model: název modelu — musí odpovídat tomu co bylo staženo v build time
# POZOR: příkaz je whisper-ctranslate2, ne faster-whisper (to je pouze Python knihovna bez CLI)
whisper-ctranslate2 audio.mp3 --model medium --model_dir /opt/whisper_models --language en \
  --output_format vtt \
  --output_dir /tmp/whisper/ \
  --initial_prompt "BBQ, brisket, bark, stall, tallow, smoke ring, tallow injection, spritzing, \
Traeger, Kamado Joe, Weber, Big Green Egg, offset smoker, pellet grill, \
pulled pork, pork butt, pork shoulder, St. Louis ribs, spare ribs, baby back, \
dry rub, wet rub, marinade, brine, mop sauce, burnt ends, flat, point, \
internal temperature, probe tender, thermometer, Thermapen, Meater, \
Aaron Franklin, Malcom Reed, Mad Scientist BBQ, Chud's BBQ, kosher salt, coarse pepper"
```

Model `medium` je dobrý kompromis — zvládne terminologii i přízvuky, na běžném VPS poběží ~2–5 minut na hodinové video (jede jako Sidekiq job na pozadí, real-time nepotřebuješ).

> **⚠️ Serverové požadavky pro Whisper (Hetzner):** `whisper-ctranslate2` s modelem `medium` (interně faster-whisper) vyžaduje ~5 GB RAM jen pro sebe. K tomu Rails app + Sidekiq + PostgreSQL + Redis = celková potřeba **minimálně 8 GB RAM**.
>
> **Doporučený Hetzner plán: CX32** (4 vCPU, 8 GB RAM, 80 GB NVMe, 20 TB traffic) — ~€6.80/měsíc.
>
> | Hetzner plán | RAM | Vhodný? | Cena/měsíc |
> |---|---|---|---|
> | CX22 | 4 GB | ❌ Nestačí — OOM kill při Whisper | ~€3.99 |
> | **CX32** | **8 GB** | **✅ Minimum pro model medium** | **~€6.80** |
> | CX42 | 16 GB | ✅ Komfort, model large možný | ~€16.40 |
>
> **Free tier:** Hetzner free tier **neexistuje**. Noví uživatelé dostávají **€20 kredit** — pokryje ~3 měsíce na CX32 pro vývoj a testování.
>
> **Whisper fronta musí mít limit 1 worker** (viz `sidekiq.yml`) — paralelní Whisper joby by způsobily OOM kill i na CX32.

**Cleanup dočasných audio souborů:** Hodinové video stažené jako MP3 = ~50–100 MB. Audio smaž vždy po zpracování — i při selhání:

```ruby
# jobs/fetch_transcript_job.rb (Whisper větev)
def transcribe_with_whisper(video)
  audio_path  = download_audio(video)   # yt-dlp -x --audio-format mp3
  whisper_vtt = run_whisper(audio_path) # vrátí cestu k .vtt souboru v /tmp/whisper/
ensure
  FileUtils.rm_f(audio_path)  if audio_path  && File.exist?(audio_path)
  FileUtils.rm_f(whisper_vtt) if whisper_vtt && File.exist?(whisper_vtt)
  # POZOR: bez --output_format vtt by Whisper generoval více souborů (.txt, .srt, .tsv...)
  # a cleanup by bylo nutné řešit přes Dir.glob. --output_format vtt zajistí jeden soubor.
end
```

**Cleanup dočasných VTT souborů:** yt-dlp při stahování titulků (`--write-subs`, `--write-auto-subs`) zapisuje `.vtt` soubory na disk. Bez cleanup se hromadí — backfill 30 videí = 30 `.vtt` souborů. Vždy smazat i při selhání:

```ruby
# jobs/fetch_transcript_job.rb (titulky větev)
def fetch_subtitles(video)
  vtt_path = download_vtt(video)   # yt-dlp --write-subs / --write-auto-subs
  process_vtt(vtt_path)
ensure
  FileUtils.rm_f(vtt_path) if vtt_path && File.exist?(vtt_path)
end
```

> Bez `ensure` se soubory hromadí i po selhání jobu — backfill 30 videí = až 3 GB dočasných dat na disku.

| Model | RAM | Rychlost | Přesnost |
|---|---|---|---|
| `base` | ~1 GB | rychlý | slabší |
| `medium` | ~5 GB | střední | **doporučeno** |
| `large` | ~10 GB | pomalý | nejlepší |

Model `VideoTranscript`:

```
- youtube_video             (belongs_to)
- source_type               (string) — 'manual_subtitles' | 'whisper_local' | 'auto_captions_youtube'
- raw_transcript            (text)
- cleaned_transcript        (text)
- language                  (string)
- available                 (boolean)
- word_count                (integer) — počet slov cleaned_transcript, plní se automaticky před uložením
- transcript_quality_score  (integer) — jednoduchá heuristika: manual_subtitles=3, whisper_local=2, auto_captions_youtube=1; slouží admin UI pro filtrování a prioritizaci ručního review
- captions_source_detail    (string) — detail zdroje pro dohledání a případné přepracování
```

`transcript_quality_score` se plní automaticky podle `source_type` — bez manuálního vstupu, bez ML:

```ruby
# models/video_transcript.rb
before_save :set_quality_score
before_save :set_word_count

QUALITY_SCORES = {
  'manual_subtitles'       => 3,
  'whisper_local'          => 2,
  'auto_captions_youtube'  => 1
}.freeze

def set_quality_score
  self.transcript_quality_score = QUALITY_SCORES.fetch(source_type, 0)
end

def set_word_count
  self.word_count = cleaned_transcript&.split&.size || 0
end
```

### 4. Čištění přepisu

- Odstranění VTT tagů a časových značek
- Deduplikace řádků (auto-titulky mají hodně opakování) — **viz sliding-window algoritmus níže**
- Spojení do čitelného textu
- **Celý přepis se vždy ukládá bez ořezu** — hodinová videa mají důležité informace i ve druhé půlce (finální výsledek, tipy, shrnutí). Blog dostane kompletní přepis a sám rozhodne jak ho zpracuje.
- `word_count` se ukládá pro monitoring (orientační přehled velikosti přepisů v admin UI)

> **Poznámka pro blog:** Hodinové video = ~8 000–12 000 slov. Při zpracování AI promptem na blogu počítej s tím že Claude / GPT-4o zvládnou celý přepis najednou, ale cena roste s délkou. Pokud by se ukázalo že kratší chunky dávají lepší výsledky pro extrakci receptů, řeší se to výhradně na straně blogu — pipeline vždy dodá kompletní přepis.

#### VTT cleaner — specifikace a implementace

YouTube auto-captions používají **rolling captions** — každý řádek se překrývá s předchozím a opakuje část textu. Naivní deduplikace (porovnání celých řádků) nestačí.

**Příklad raw VTT z auto-captions:**
```
00:00:01.000 --> 00:00:03.000
so today we're gonna

00:00:02.500 --> 00:00:05.000
so today we're gonna talk about brisket

00:00:04.000 --> 00:00:07.000
talk about brisket and what makes
```

**Výsledek naivní deduplikace** (špatně):
```
so today we're gonna  so today we're gonna talk about brisket  talk about brisket and what makes
```

**Výsledek sliding-window deduplikace** (správně):
```
so today we're gonna talk about brisket and what makes
```

**Algoritmus:** porovnáváme suffix předchozího řádku s prefixem aktuálního. Pokud se překrývají, odřízneme překryv a přidáme pouze novou část.

```ruby
# services/blog/vtt_cleaner.rb
class VttCleaner
  # Odstraní VTT hlavičku, tagy a časové značky — vrátí pole čistých řádků
  # POZOR: původní regex /^\d{2}:\d{2}/ by zachytil i text začínající "10: Add the rub" apod.
  # Zpřesněný pattern matchuje pouze skutečný VTT timestamp formát: HH:MM:SS.mmm --> HH:MM:SS.mmm
  def self.strip_vtt(raw_vtt)
    raw_vtt
      .lines
      .reject { |l| l =~ /^WEBVTT|^\d{2}:\d{2}:\d{2}\.\d{3} --> |^$|<[^>]+>/ }
      .map(&:strip)
      .reject(&:empty?)
  end

  # Sliding-window deduplikace rolling captions
  # Hledá nejdelší suffix předchozího řádku který je prefixem aktuálního
  def self.deduplicate(lines)
    return lines if lines.size < 2

    result = [lines.first]
    lines.each_cons(2) do |prev, curr|
      overlap = longest_suffix_prefix_overlap(prev, curr)
      new_part = curr[overlap..].strip
      result << new_part unless new_part.empty?
    end
    result
  end

  def self.longest_suffix_prefix_overlap(a, b)
    max_check = [a.length, b.length].min
    max_check.downto(1) do |len|
      return len if a.end_with?(b[0, len])
    end
    0
  end

  # Hlavní metoda — vrátí čistý plain text
  def self.call(raw_vtt)
    lines     = strip_vtt(raw_vtt)
    deduped   = deduplicate(lines)
    deduped.join(' ').gsub(/\s{2,}/, ' ').strip
  end
end
```

**Test cases pro VttCleaner** — přidat do specs:

```ruby
# spec/services/blog/vtt_cleaner_spec.rb
RSpec.describe VttCleaner do
  it "deduplikuje rolling captions" do
    lines = [
      "so today we're gonna",
      "so today we're gonna talk about brisket",
      "talk about brisket and what makes"
    ]
    result = VttCleaner.deduplicate(lines)
    expect(result.join(' ')).to eq("so today we're gonna talk about brisket and what makes")
  end

  it "zachová řádky bez překryvu" do
    lines = ["First sentence.", "Second sentence."]
    expect(VttCleaner.deduplicate(lines).join(' ')).to eq("First sentence. Second sentence.")
  end

  it "odstraní VTT tagy a časové značky" do
    raw = "WEBVTT\n\n00:00:01.000 --> 00:00:03.000\n<c>hello world</c>\n"
    expect(VttCleaner.call(raw)).to eq("hello world")
  end

  it "vrátí prázdný string pro prázdný vstup" do
    expect(VttCleaner.call("")).to eq("")
    expect(VttCleaner.call("WEBVTT\n\n")).to eq("")
  end

  it "zvládne single-line vstup bez pádu" do
    lines = ["only one line"]
    expect(VttCleaner.deduplicate(lines)).to eq(["only one line"])
  end

  it "deduplikuje vstup kde jsou všechny řádky identické" do
    lines = ["brisket", "brisket", "brisket"]
    result = VttCleaner.deduplicate(lines).join(' ')
    expect(result).to eq("brisket")
  end
end
```

> **Poznámka:** Manuální titulky a Whisper výstup rolling captions typicky nemají — u nich stačí základní strip + join. Sliding-window deduplikace se uplatní hlavně u `auto_captions_youtube` větve. `VttCleaner.call` lze volat pro všechny zdroje bez podmínek — na čistém textu deduplikace nemá vedlejší efekty.

### 5. Webhook notifikace blogu

Po přechodu do stavu `transcript_ready` pipeline pingne blog POST requestem. Každý request je podepsán HMAC-SHA256 signaturou — blog ověří signaturu a odmítne requesty s neplatným podpisem.

```ruby
# services/blog/webhook_service.rb
payload_json = payload.to_json
signature = OpenSSL::HMAC.hexdigest('SHA256', ENV['BLOG_WEBHOOK_SECRET'], payload_json)

# POZOR: X-Api-Key používá samostatný klíč — NIKDY neposílej BLOG_WEBHOOK_SECRET v hlavičce,
# protože kdokoliv kdo request zachytí by mohl generovat platné HMAC podpisy.
HTTP.headers(
  'Content-Type'    => 'application/json',
  'X-Api-Key'       => ENV['BLOG_API_KEY'],
  'X-Hub-Signature' => "sha256=#{signature}"
).post(ENV['BLOG_WEBHOOK_URL'], body: payload_json)
```

```ruby
# Blog strana — ověření signatury
def valid_signature?(request)
  expected = OpenSSL::HMAC.hexdigest('SHA256', ENV['BLOG_WEBHOOK_SECRET'], request.raw_post)
  received = request.headers['X-Hub-Signature'].to_s.delete_prefix('sha256=')
  ActiveSupport::SecurityUtils.secure_compare(expected, received)
end

def receive_webhook
  return head :unauthorized unless valid_signature?(request)
  # ...
end
```

Payload:
```ruby
{
  event:          'transcript_ready',
  video_id:       video.youtube_video_id,
  title:          video.title,
  channel:        video.youtube_channel.name,
  transcript_url: "#{ENV['APP_URL']}/api/v1/transcripts/#{video.youtube_video_id}"
}
```

Blog pak zavolá `GET /api/v1/transcripts/:video_id` a dostane celý přepis.

### 6. Interní API pro blog

```
GET /api/v1/transcripts/:video_id
  → { video_id, title, channel, published_at, language, cleaned_transcript, source_type }
  # language: důležité pro blog — anglický přepis vyžaduje jiný prompt než český

GET /api/v1/videos?status=transcript_ready&webhook_sent_at=null
  → seznam videí s hotovým přepisem, která ještě nebyla notifikována webhookem

GET /api/v1/videos?queued_for_blog=true
  → seznam videí manuálně označených redaktorem ke zpracování

PATCH /api/v1/videos/:video_id
  → { queued_for_blog: true } — manuální označení z admin UI
```

Autentizace: API klíč v hlavičce `X-Api-Key` (statický secret, sdílený s blogem).

**Databázové indexy pro API dotazy:**

Dotazy jako `?status=transcript_ready&webhook_sent_at=null` bez indexů způsobí full table scan. Přidej do migrace:

```ruby
# db/migrate/XXXXXX_add_indexes_to_youtube_videos.rb
add_index :youtube_videos, :processing_status
add_index :youtube_videos, :webhook_sent_at
add_index :youtube_videos, :queued_for_blog
# Composite index pro nejčastější dotaz (videa čekající na webhook notifikaci)
add_index :youtube_videos, [:processing_status, :webhook_sent_at]
# Composite index pro recover_stuck_videos (processing_status + updated_at)
add_index :youtube_videos, [:processing_status, :updated_at]
```

### 7. Stavový automat pipeline

```
new → metadata_fetched → transcript_ready
        ↘ failed            ↘ failed
        ↘ skipped
```

`skipped` je konečný stav — ne chyba, jen video které pipeline záměrně vyloučila. Důvod je vždy uložen v `failed_reason`:

| `failed_reason` | Příčina |
|---|---|
| `live_content` | Živý přenos, premiéra nebo replay (`live_status != 'not_live'`) |
| `short_video` | URL obsahuje `/shorts/` nebo video kratší než 120 sekund (záchrana pro Shorts bez správné URL) |

Každý stav odpovídá jednomu background jobu. Selhání v jakémkoliv kroku zapíše `failed_reason` a přechod do `failed`.

**Retry strategie:** každý job má Sidekiq retry s exponenciálním backoffem (3 pokusy, prodleva 5 min / 15 min / 45 min). Po vyčerpání pokusů → `failed`. Důvod: yt-dlp občas selže kvůli dočasné nedostupnosti nebo rate limitu — druhý pokus za 5 minut obvykle uspěje.

> **⚠️ Sidekiq výchozí backoff nestačí:** Sidekiq výchozí interval pro první retry je ~15 sekund (`(retry_count ** 4) + 15 + rand(30)`), ne 5 minut. Pro yt-dlp rate limiting je to příliš krátké. Nastavit custom intervaly explicitně:

```ruby
# jobs/fetch_transcript_job.rb (stejný pattern pro ProcessVideoJob a NotifyBlogJob)
sidekiq_options retry: 3

sidekiq_retry_in do |count, _exception|
  case count
  when 0 then 5  * 60   # 5 minut  — první retry
  when 1 then 15 * 60   # 15 minut — druhý retry
  else        45 * 60   # 45 minut — třetí retry
  end
end

def perform(video_id)
  video = YoutubeVideo.find(video_id)
  # ... zpracování ...
rescue StandardError => e
  # Inkrementuj retry_count při každém selhání — pole existuje na modelu, ale bez tohoto
  # rescue bloku by zůstalo navždy na 0 (mrtvý kód). Viditelné v admin UI pro diagnostiku.
  video&.increment!(:retry_count)
  raise  # vždy znovu vyhodit — Sidekiq musí chybu dostat pro retry mechanismus
end
```

**Recovery videí ve stavu `failed`:** Sidekiq retry pokryje přechodná selhání, ale po vyčerpání pokusů video uvázne ve stavu `failed` navždy. Backfill 30 videí nového kanálu může hned na startu přinést 5–8 failed videí (yt-dlp rate limit, dočasná nedostupnost). Bez recovery nástroje v MVP jsou tato videa ztracena do post-MVP admin rozhraní.

Rake task pro manuální re-queue failed videí — přidat do MVP:

```ruby
# lib/tasks/pipeline.rake
namespace :pipeline do
  # Znovu zařadí všechna failed videa do fronty
  # Použití: rails pipeline:retry_failed
  # Filtrování: rails pipeline:retry_failed CHANNEL=UCxyz123
  desc "Re-queue failed videos for reprocessing"
  task retry_failed: :environment do
    scope = YoutubeVideo.where(processing_status: 'failed')
    scope = scope.joins(:youtube_channel)
                 .where(youtube_channels: { channel_id: ENV['CHANNEL'] }) if ENV['CHANNEL']

    count = scope.count
    abort "Žádná failed videa nenalezena." if count.zero?

    puts "Re-queueing #{count} failed videí..."
    scope.find_each do |video|
      video.update!(processing_status: 'new', failed_reason: nil, retry_count: 0)
      ProcessVideoJob.perform_later(video.id)
      puts "  ↻ #{video.youtube_video_id} — #{video.title}"
    end
    puts "Hotovo."
  end
end
```

> **Idempotence:** `ProcessVideoJob` zkontroluje stav na začátku (`return if video.transcript_ready?`) — opakované spuštění rake tasku je bezpečné.

`ChannelPollingJob` proto při každém spuštění (každých 6h) zkontroluje videa zaseklá v přechodovém stavu déle než 30 minut a re-enqueue je:

```ruby
# channel_polling_job.rb — přidat před RSS polling
def recover_stuck_videos
  # metadata_fetched déle než 30 min = FetchTranscriptJob se nikdy nespustil
  YoutubeVideo.where(processing_status: 'metadata_fetched')
              .where('updated_at < ?', 30.minutes.ago)
              .joins(:youtube_channel).where(youtube_channels: { active: true })
              .find_each do |video|
                Rails.logger.warn "[Recovery] Re-enqueueing stuck video #{video.youtube_video_id}"
                FetchTranscriptJob.perform_later(video.id)
              end

  # new déle než 60 min = ProcessVideoJob se nikdy nespustil (vzácnější, ale možné)
  YoutubeVideo.where(processing_status: 'new')
              .where('updated_at < ?', 60.minutes.ago)
              .joins(:youtube_channel).where(youtube_channels: { active: true })
              .find_each do |video|
                Rails.logger.warn "[Recovery] Re-enqueueing stuck new video #{video.youtube_video_id}"
                ProcessVideoJob.perform_later(video.id)
              end
end
```

> **Idempotence:** `ProcessVideoJob` a `FetchTranscriptJob` musí být idempotentní — při re-enqueue nesmí duplikovat data. Každý job zkontroluje aktuální stav videa na začátku a přeskočí zpracování pokud video mezitím postoupilo dál (`return if video.transcript_ready?`).

---

## Architektura — service objekty

```
app/
  jobs/
    channel_polling_job.rb       # Pravidelná kontrola RSS feedů (každých 6h)
    process_video_job.rb         # Orchestrátor — spouští kroky pipeline
    fetch_transcript_job.rb      # Volá TranscriptService (fronta yt_dlp, max 3 paralelně)
    notify_blog_job.rb           # Volá WebhookService po transcript_ready

  services/
    youtube/
      rss_poller.rb              # Parsuje RSS feed kanálu
      video_metadata_service.rb  # yt-dlp --dump-json
      transcript_service.rb      # yt-dlp --write-subs, čištění VTT
    blog/
      webhook_service.rb         # POST na blog webhook
      vtt_cleaner.rb             # Čistí raw VTT na plain text

  controllers/api/v1/
    transcripts_controller.rb    # GET /api/v1/transcripts/:video_id
    videos_controller.rb         # GET + PATCH /api/v1/videos
```

---

## Pipeline — krok za krokem

```
1. ChannelPollingJob (každých 6h)
   └─ RssPoller.call(channel)
      └─ Projde RSS feed, najde nová video ID
         └─ Pro každé nové: find_or_create_by!(youtube_video_id:) — atomické, bezpečné při souběhu
              └─ Enqueue ProcessVideoJob (pouze pro previously_new_record?)

2. ProcessVideoJob
   └─ VideoMetadataService.call(video)
      └─ yt-dlp --dump-json
         └─ Uloží duration_seconds z metadat
            ├─ live_status != 'not_live' → status: 'skipped', failed_reason: 'live_content' → STOP
            ├─ URL /shorts/ nebo duration < 120s → status: 'skipped', failed_reason: 'short_video' → STOP
            └─ status: 'metadata_fetched'
                 └─ Enqueue FetchTranscriptJob (fronta: yt_dlp, max 3 paralelně)

3. FetchTranscriptJob
   └─ TranscriptService.call(video)
      ├─ yt-dlp --write-subs → manuální titulky nalezeny?
      │    └─ ANO → VttCleaner → uloží VideoTranscript (source: manual_subtitles)
      │         └─ status: 'transcript_ready' → Enqueue NotifyBlogJob
      ├─ NE → whisper-ctranslate2 (yt-dlp stáhne audio, Whisper přepíše) [fronta: whisper, max 1]
      │    └─ VttCleaner → uloží VideoTranscript (source: whisper_local)
      │         └─ status: 'transcript_ready' → Enqueue NotifyBlogJob
      │    [ensure: smaž dočasný audio soubor — hodinové MP3 = ~50–100 MB]
      └─ Whisper selže → yt-dlp --write-auto-subs (záchrana)
           ├─ auto-captions nalezeny → uloží (source: auto_captions_youtube)
           │    └─ status: 'transcript_ready' → Enqueue NotifyBlogJob
           └─ nic nenalezeno → status: 'failed', failed_reason: 'no_transcript'

4. NotifyBlogJob
   └─ WebhookService.call(video)
      ├─ blog odpoví 2xx → video.update!(webhook_sent_at: Time.current) + log info "Blog notified"
      └─ jinak → Sidekiq retry (3x s backoffem)
```

---

## Integrace

| Potřeba | Řešení | Poznámka |
|---|---|---|
| Detekce nových videí | YouTube RSS Atom feed | Bez API klíče |
| Metadata + titulky | yt-dlp CLI | Nainstalovaný v Dockeru, verze fixovaná, max 3 paralelně |
| Přepis bez manuálních titulků | whisper-ctranslate2 (local) | Zdarma, běží v Dockeru, model medium — CLI wrapper nad faster-whisper |
| YouTube auto-captions | yt-dlp `--write-auto-subs` | Záchrana pokud Whisper selže |
| Notifikace blogu | Webhook (POST) | Blog si pak stáhne přepis přes API |
| Background joby | Sidekiq + Redis | Standardní Rails setup |
| Speech-to-text fallback | whisper-ctranslate2 | Součást MVP (ne post-MVP) |

---

## Docker setup

```dockerfile
# Dockerfile
FROM ruby:3.3-slim

# Systémové závislosti — curl a unzip nutné pro instalaci Dena
RUN apt-get update && apt-get install -y ffmpeg python3.11 python3.11-venv curl unzip

# Deno — povinný JavaScript runtime pro yt-dlp (YouTube JS výzvy)
# Bez Dena yt-dlp YouTube od ~2025 nepodporuje vůbec
# ⚠️ Fixovaná verze — curl pipe do sh by vždy stáhl latest a narušil reprodukovatelnost buildů
RUN curl -fsSL https://github.com/denoland/deno/releases/download/v2.2.3/deno-x86_64-unknown-linux-gnu.zip \
    -o /tmp/deno.zip \
 && unzip /tmp/deno.zip -d /usr/local/bin/ \
 && rm /tmp/deno.zip
# Ověření instalace:
# RUN deno --version

# Python venv předejde konfliktu se systémovým Pythonem
# yt-dlp-ejs: nutný package pro propojení yt-dlp ↔ Deno
# whisper-ctranslate2: CLI wrapper nad faster-whisper — poskytuje příkaz `whisper-ctranslate2` v shellu
#   (faster-whisper samotný CLI nemá — volání `faster-whisper audio.mp3` by selhalo s "command not found")
RUN python3.11 -m venv /opt/pyenv \
 && /opt/pyenv/bin/pip install yt-dlp==2026.03.17 yt-dlp-ejs \
 && /opt/pyenv/bin/pip install whisper-ctranslate2==0.4.4
# ⚠️ Před nasazením ověř aktuální verzi: pip index versions whisper-ctranslate2
ENV PATH="/opt/pyenv/bin:/usr/local/bin:$PATH"

# Pre-download Whisper model medium při build time (Varianta A)
# Model ~1.5 GB — bez tohoto kroku by se stahoval při prvním jobu za provozu → timeout / OOM
# whisper-ctranslate2 interně používá faster-whisper — WhisperModel import funguje stejně
RUN python3.11 -c "from faster_whisper import WhisperModel; WhisperModel('medium', download_root='/opt/whisper_models')"
ENV WHISPER_MODEL_PATH=/opt/whisper_models
# ... Rails setup
```

> **Poznámka k aktualizaci yt-dlp:** YouTube se mění. Verzi vědomě aktualizuj — při každé aktualizaci ověř changelog na [github.com/yt-dlp/yt-dlp/releases](https://github.com/yt-dlp/yt-dlp/releases). Upgrade Dena probíhá změnou čísla verze v URL v Dockerfilu (`/download/v2.x.x/deno-x86_64...`) — záměrně fixovaná verze, ne latest.

```yaml
# docker-compose.yml
services:
  web:    # Rails app
  worker: # Sidekiq
  db:     # PostgreSQL
  redis:  # Pro Sidekiq
```

```yaml
# config/sidekiq.yml
concurrency: 10
queues:
  - [critical, 10]   # stavové přechody, notifikace
  - [default, 5]     # obecné joby
  - [yt_dlp, 3]      # max 3 paralelní yt-dlp joby (metadata, titulky) — rate limit YouTube
  - [whisper, 1]     # max 1 Whisper job najednou — faster-whisper medium = ~5 GB RAM, více by způsobilo OOM
  - [backfill, 1]    # backfill nových kanálů — nízká priorita, nespěchá
```

> **Poznámka:** `yt_dlp` a `whisper` jsou záměrně oddělené fronty. `yt_dlp` (metadata + titulky) může běžet 3 paralelně bez RAM problémů. `whisper` je omezen na 1 — načtení modelu `medium` vyžaduje ~5 GB RAM a paralelní běh by způsobil OOM kill nebo výrazné zpomalení na běžném VPS.

**Sidekiq Web UI — autentizace:**

`/sidekiq` bez ochrany je na produkčním serveru bezpečnostní problém — kdokoliv může prohlížet joby, mazat fronty nebo spouštět retry. Zabezpeč HTTP Basic Auth:

```ruby
# config/routes.rb
require 'sidekiq/web'

Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(username),
    ::Digest::SHA256.hexdigest(ENV.fetch('SIDEKIQ_WEB_USERNAME'))
  ) &
  ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(password),
    ::Digest::SHA256.hexdigest(ENV.fetch('SIDEKIQ_WEB_PASSWORD'))
  )
end

mount Sidekiq::Web => '/sidekiq'
```

```bash
# .env
SIDEKIQ_WEB_USERNAME=admin
SIDEKIQ_WEB_PASSWORD=dlouhe-nahodne-heslo
```

> `secure_compare` přes SHA256 digest předchází timing útokům při porovnávání credentials.

---

## Rizika a slabá místa

| Riziko | Pravděpodobnost | Řešení |
|---|---|---|
| Whisper model cache po restartu kontejneru | Vysoká (bez opravy) | Pre-download modelu v Dockerfilu (Varianta A) nebo Docker volume (Varianta B) — viz sekce Whisper setup |
| Titulky nedostupné | 15–25 % videí | Whisper local jako fallback (MVP), auto-captions jako záchrana |
| Nízká kvalita auto-captions u BBQ obsahu | Vysoká | Whisper local s BBQ initial_prompt má výrazně lepší přesnost |
| yt-dlp přestane fungovat po YouTube změně | Nízká (opravy vychází rychle) | Monitorovat joby, fixovat verzi v Dockeru, vědomě aktualizovat |
| Blog webhook selže | Nízká–střední | Retry logika v NotifyBlogJob, blog si může vyžádat přepis i ručně přes API |
| Rate limiting yt-dlp od YouTube | Nízká–střední | Max 3 paralelní yt-dlp joby, backoff retry |
| Duplicate RSS záznamy / race condition | Možné | `find_or_create_by!` + unique index jako pojistka + `rescue ActiveRecord::RecordNotUnique` pro čisté ošetření souběhu |
| VTT temp soubory po selhání jobu | Střední (bez ensure) | `ensure FileUtils.rm_f` v titulkové i Whisper větvi — backfill 30 videí jinak = desítky MB temp dat |
| Shorts a Reels v RSS feedu | Střední (aktivní kanály je publikují často) | Detekce přes URL `/shorts/` (primární) + `duration < 120s` (záchrana) v `ProcessVideoJob`, stav `skipped` |
| Živé přenosy a premiéry v RSS feedu | Nízká–střední | Detekce přes `live_status != 'not_live'` v `ProcessVideoJob`, stav `skipped` |
| Backfill nového kanálu zahltí frontu | Nízká | Backfill joby zařadit do nízké priority fronty, yt_dlp limit platí i pro backfill |
| RSS feed vrací pouze posledních ~15 videí | Nízká–střední | Při výpadku >15 videí kanálu propadnou mimo RSS okno — zachytí je pouze manuální backfill. Za normálního provozu (polling každých 6h) problém nenastane. **Ochrana:** monitoring `last_checked_at` — alert pokud jakýkoliv aktivní kanál nebyl zkontrolován déle než 24h (viz Observability). |
| OOM kill při souběžném Whisper zpracování | Nízká (řešeno frontou) | Fronta `whisper` má limit 1 worker — model medium = ~5 GB RAM, více instancí by zahltilo VPS. **Minimum: Hetzner CX32 (8 GB RAM).** |
| Sidekiq Web UI bez autentizace | Střední (výchozí stav Rails) | HTTP Basic Auth přes `Rack::Auth::Basic` s `secure_compare` — viz Docker setup sekce |
| YouTube Terms of Service | Vědomé riziko | Použití yt-dlp pro komerční content generation (psaní článků) je v šedé zóně YouTube ToS (sekce 5.B). Toto nebrání implementaci, ale je to vědomé rozhodnutí. Riziko: zablokování IP/účtu, ne právní postih vůči provozovateli blogu. |

---

## Observability

- Logování každého kroku pipeline (Rails logger)
- `failed_reason` na modelu pro dohledání příčiny selhání
- `retry_count` na modelu pro sledování nestabilních videí
- Sidekiq Web UI pro přehled jobů
- Základní admin přehled videí a jejich stavů (post-MVP)
- **Monitoring `last_checked_at`:** alert pokud jakýkoliv aktivní kanál nemá `last_checked_at` aktualizovaný déle než 24h — indikuje výpadek `ChannelPollingJob` nebo RSS chybu. Lze implementovat jako jednoduchý rake task nebo Sidekiq scheduled check:

```ruby
# Přidat do ChannelPollingJob nebo jako standalone scheduled job (každých 12h)
stale = YoutubeChannel.where(active: true)
                      .where('last_checked_at < ? OR last_checked_at IS NULL', 24.hours.ago)
if stale.any?
  Rails.logger.error "[Alert] #{stale.count} kanálů nebylo zkontrolováno déle než 24h: #{stale.pluck(:name).join(', ')}"
  # post-MVP: poslat email / Slack notifikaci
end
```

---

## Priority MVP

1. RSS polling + ukládání nových videí
2. yt-dlp metadata + titulky (fronta s limitem 3 paralelně)
3. VTT čištění + uložení přepisu
4. Stavový automat + retry logika s backoffem
5. Interní API (GET transcript, GET/PATCH videos)
6. Webhook notifikace blogu
7. Rake task `pipeline:retry_failed` — re-queue failed videí (kritické pro backfill)
8. Základní admin přehled

Automatické publikování článků není součástí MVP.
AI analýza a zpracování obsahu probíhá výhradně na blogu.

---

## Post-MVP

- Admin rozhraní s náhledem přepisů a možností znovu-spustit krok
- Automatické tagování a detekce tématu (recept / recenze / technika) — na straně blogu nebo pipeline
- Notifikace při selhání webhooků (email / Slack)
- Webhook místo RSS pollingu (YouTube PubSubHubbub)

---

---

# Implementační plán: Blog strana

## Kontext

Blog má nastavená pravidla pro psaní článků (tone of voice, struktura, styl). Pipeline mu dodá čistý anglický přepis. Blog z něj sestaví článek v češtině podle svých pravidel.

---

## Co blog dostane od pipeline

```json
{
  "video_id": "abc123",
  "title": "Ultimate Brisket Guide",
  "channel": "BBQ with Franklin",
  "published_at": "2025-03-15T10:00:00Z",
  "source_type": "auto_captions",
  "cleaned_transcript": "Today we're going to talk about brisket..."
}
```

---

## Co blog potřebuje implementovat

### 1. Webhook endpoint

Blog přijme POST z pipeline a spustí zpracování. Ověřuje HMAC-SHA256 signaturu z hlavičky `X-Hub-Signature`:

```
POST /webhooks/bbq-pipeline
Headers:
  X-Api-Key:       <shared_secret>
  X-Hub-Signature: sha256=<hmac_signature>
Body: { "event": "transcript_ready", "video_id": "abc123", "transcript_url": "..." }
```

```ruby
# Pseudokód — přizpůsob svému stacku
def receive_webhook
  return head :unauthorized unless valid_signature?(request)

  video_id       = params[:video_id]
  transcript_url = params[:transcript_url]

  # fetch_transcript patří DO jobu — ne zde synchronně
  ProcessTranscriptJob.perform_later(video_id, transcript_url)

  head :ok
end

private

def valid_signature?(request)
  expected = OpenSSL::HMAC.hexdigest('SHA256', ENV['BLOG_WEBHOOK_SECRET'], request.raw_post)
  received = request.headers['X-Hub-Signature'].to_s.delete_prefix('sha256=')
  ActiveSupport::SecurityUtils.secure_compare(expected, received)
end
```

### 2. Stažení přepisu z pipeline API

Fetch probíhá **uvnitř jobu** (ne v controlleru) — výpadek pipeline API tím pádem zachytí Sidekiq retry, ne webhook timeout:

```ruby
# ProcessTranscriptJob
def perform(video_id, transcript_url)
  response = HTTP.headers('X-Api-Key' => ENV['PIPELINE_API_KEY']).get(transcript_url)
  transcript = JSON.parse(response.body)
  # ... AI zpracování
end
```

> **Idempotence:** Blog musí použít `upsert` na `video_id` místo prostého insertu. Pokud `NotifyBlogJob` selže až na 3. pokus a blog video zpracoval při 1. pokusu, další trigger by vytvořil duplicitní záznam. `upsert` tento případ bezpečně ošetří. **Pozor:** Rails `upsert` bez explicitního `unique_by` pracuje podle primárního klíče — správně:
> ```ruby
> BlogVideo.upsert(attributes, unique_by: :video_id)
> ```

### 3. AI zpracování přepisu

Zde blog použije svůj stávající AI setup (tone of voice, pravidla pro psaní). Přepis přijde v angličtině — blog ho zpracuje a přeloží do češtiny podle svých pravidel.

**Doporučená struktura promptu:**

```
Jsi redaktor blogu o grilování. Máš k dispozici přepis anglického YouTube videa.
Tvým úkolem je připravit podklady pro článek v češtině.

[Zde vložit tvá stávající pravidla — tone of voice, struktura článku, styl psaní]

Přepis videa:
---
{cleaned_transcript}
---

Připrav:
1. Shrnutí videa (2–3 věty česky)
2. Hlavní tipy a poznatky (bullet body česky)
3. Suroviny a vybavení (pokud zmíněny)
4. Postup / kroky (pokud jde o recept)
5. Návrh osnovy článku
6. Hodnocení relevance pro náš blog (1–10) + zdůvodnění

Výstup jako JSON.
```

> **Klíčové:** Pravidla tone of voice a struktury článku přidej přímo do promptu — blog je má nastavená, stačí je sem vložit. Překlad a lokalizace do češtiny proběhne rovnou v tomto kroku.

### 4. Uložení výstupu a review

Blog uloží AI výstup a zobrazí ho redaktorovi ke kontrole:

```
- summary_cs         (text) — shrnutí česky
- tips_cs            (text) — tipy česky
- ingredients        (text)
- steps              (text)
- article_outline    (text)
- relevance_score    (integer 1–10)
- relevance_reason   (text)
- raw_transcript     (text) — uložit pro případ potřeby
- status             (string) — 'pending_review' | 'approved' | 'published' | 'rejected'
```

### 5. Redakční workflow

```
transcript_received
  → AI zpracování (automaticky)
    → pending_review (redaktor zkontroluje)
      ├─ approved → redaktor dopíše článek a publikuje
      └─ rejected → ignorovat nebo znovu zpracovat
```

---

## Implementační pořadí (blog strana)

1. **Webhook endpoint** — přijmout POST z pipeline, ověřit API klíč, odpovědět 200
2. **Fetch přepisu** — stáhnout cleaned_transcript z pipeline API
3. **AI prompt** — vložit pravidla blogu, zpracovat přepis, uložit výstup
4. **Admin přehled** — seznam zpracovaných videí se statusem a výstupem
5. **Redakční review** — approve / reject + editace před publikací

---

## Sdílené secrets (pipeline ↔ blog)

| Proměnná | Kde | Popis |
|---|---|---|
| `PIPELINE_API_KEY` | blog `.env` | Klíč pro volání pipeline API |
| `BLOG_WEBHOOK_URL` | pipeline `.env` | URL webhook endpointu na blogu — **musí být HTTPS**; HMAC chrání integritu payloadu, ale ne jeho confidencialitu |
| `BLOG_WEBHOOK_SECRET` | oba | Shared secret výhradně pro HMAC-SHA256 podpis — nikdy neposílat v hlavičce |
| `BLOG_API_KEY` | oba | Samostatný klíč pro `X-Api-Key` autentizaci webhooků — oddělený od HMAC secretu |

---

## Časová osa (odhad)

| Fáze | Co | Odhad |
|---|---|---|
| 1 | Pipeline MVP (RSS → přepis → API) | 2–3 týdny |
| 2 | Blog webhook + fetch přepisu | 2–3 dny |
| 3 | AI prompt + uložení výstupu | 1–2 dny |
| 4 | Redakční admin přehled | 2–3 dny |
| 5 | Ladění promptu a tone of voice | průběžně |
