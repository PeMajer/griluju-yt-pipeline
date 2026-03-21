# griluju-yt-pipeline

Interní nástroj pro blog [griluju.cz](https://griluju.cz). Automaticky sleduje zahraniční YouTube kanály o BBQ, detekuje nová videa, získává přepisy a ukládá je do databáze. Blog si přepisy stahuje přes REST API a generuje z nich české články.

Pipeline je čistě sběrný nástroj — žádná AI analýza, žádné psaní článků. To probíhá na straně blogu.

## Jak to funguje

```
YouTube RSS feed
    ↓ ChannelPollingJob (každých 6h)
    ↓ ProcessVideoJob — metadata, filtr Shorts/live
    ↓ FetchTranscriptJob
        1. manuální titulky (yt-dlp)
        2. Whisper speech-to-text (pokud titulky chybí)
        3. auto-generované titulky (záchrana)
    ↓ VttCleanerService — čistí VTT formát, deduplikuje rolling captions
    ↓ VideoTranscript uložen do DB (processing_status: transcript_ready)

Blog agent
    ↓ GET /api/v1/videos?status=completed
    ↓ GET /api/v1/transcripts/:video_id
    ↓ Vygeneruje článek, označí video: PATCH /api/v1/videos/:video_id
```

Detailní architektura: [`docs/architecture.md`](docs/architecture.md)

## Požadavky

- [OrbStack](https://orbstack.dev) (nebo Docker Desktop)
- Docker Compose

Aplikace běží celá v kontejnerech — Ruby, Python, PostgreSQL, Redis ani Whisper model lokálně instalovat nepotřebuješ.

## Lokální spuštění

```bash
# 1. Nakopíruj a vyplň env proměnné
cp .env.example .env

# 2. Postav image a spusť stack
#    Pozor: první build stáhne Whisper model medium (~1.5 GB) — může trvat 5–10 minut
docker compose up --build

# 3. Vytvoř databázi a spusť migrace (jen první spuštění)
docker compose exec web rails db:create db:migrate
```

Stack poběží na:
- **Rails API:** http://localhost:3000
- **Sidekiq Web UI:** http://localhost:3000/sidekiq (přihlašovací údaje z `.env`)

## Konfigurace

Viz [`.env.example`](.env.example) — zkopíruj do `.env` a vyplň:

| Proměnná | Popis |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection string |
| `BLOG_API_KEY` | API klíč pro blog agenta (sdílený s blogovým projektem) |
| `SIDEKIQ_WEB_USERNAME` | HTTP Basic Auth login pro Sidekiq UI |
| `SIDEKIQ_WEB_PASSWORD` | HTTP Basic Auth heslo pro Sidekiq UI |

Generování bezpečného klíče:
```bash
openssl rand -hex 32
```

## Testy

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

Inicializace testovací DB (jen první spuštění):
```bash
docker compose exec -e RAILS_ENV=test web rails db:create db:schema:load
```

## Přidání YouTube kanálu

```bash
# 1. Zjisti channel_id z URL kanálu
docker compose exec web rails channels:resolve_id URL=https://www.youtube.com/@ChannelHandle

# 2. Přidej kanál do DB
docker compose exec web rails console
YoutubeChannel.create!(
  name: "Název kanálu",
  channel_id: "UC...",
  channel_url: "https://www.youtube.com/channel/UC...",
  active: true
)
```

Kanál se automaticky zpracuje při příštím polling cyklu (každých 6h).
Nebo spusť ručně: `ChannelPollingJob.perform_now`

Detailní operační postupy: [`docs/runbook.md`](docs/runbook.md)

## Dokumentace

| Soubor | Obsah |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Stack, modely, jobs, API, indexy — technická reference |
| [`docs/runbook.md`](docs/runbook.md) | Operační postupy — přidání kanálů, monitoring, opravy |
| [`docs/lessons.md`](docs/lessons.md) | Patterny a poučení z vývoje |
| [`docs/pipeline-plan.md`](docs/pipeline-plan.md) | Původní specifikace (referenční dokument) |
