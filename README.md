# griluju-yt-pipeline

Internal data pipeline for [griluju.cz](https://griluju.cz) — a Czech BBQ blog. Monitors YouTube channels, fetches transcripts, and exposes them via REST API for downstream article generation.

## What it does

```
YouTube RSS → detect new videos → download subtitles / Whisper STT → clean transcript → store in DB
                                                                                              ↓
                                                                              Blog agent fetches via API
                                                                              and generates Czech articles
```

The pipeline is a **data collector only** — no AI analysis, no article writing. That happens on the blog side.

## Quick start

```bash
cp .env.example .env   # fill in the values
docker compose up --build
docker compose exec web rails db:create db:migrate
```

First build downloads the Whisper `medium` model (~1.5 GB). Subsequent starts are fast.

- **API:** http://localhost:3000
- **Sidekiq UI:** http://localhost:3000/sidekiq

## Tech stack

Ruby on Rails · PostgreSQL · Sidekiq · yt-dlp · Whisper (whisper-ctranslate2) · Docker Compose

## Documentation

| Document | Description |
|---|---|
| [docs/architecture.md](docs/architecture.md) | System design, data models, job pipeline, API reference |
| [docs/setup.md](docs/setup.md) | Local development setup, environment variables, testing |
| [docs/runbook.md](docs/runbook.md) | Operations: adding channels, monitoring, failure recovery |
| [docs/decisions.md](docs/decisions.md) | Key architectural decisions and the reasoning behind them |
| [docs/lessons.md](docs/lessons.md) | Hard-won lessons from development |
