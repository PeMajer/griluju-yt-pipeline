# Local Development Setup

## Prerequisites

- [OrbStack](https://orbstack.dev) or Docker Desktop
- Docker Compose

No local Ruby, Python, or PostgreSQL installation needed — everything runs in containers.

## First-time setup

```bash
# 1. Clone and enter the project
git clone https://github.com/PeMajer/griluju-yt-pipeline.git
cd griluju-yt-pipeline

# 2. Configure environment
cp .env.example .env
# Edit .env — see Environment variables below

# 3. Build and start
#    Note: first build downloads Whisper model medium (~1.5 GB), takes 5–10 min
docker compose up --build

# 4. Initialize the database (first time only)
docker compose exec web rails db:create db:migrate
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | yes | PostgreSQL connection string — matches docker-compose service |
| `REDIS_URL` | yes | Redis connection string — matches docker-compose service |
| `BLOG_API_KEY` | yes | Shared secret with the blog project (`PIPELINE_API_KEY` on their side) |
| `SIDEKIQ_WEB_USERNAME` | yes | HTTP Basic Auth login for Sidekiq UI |
| `SIDEKIQ_WEB_PASSWORD` | yes | HTTP Basic Auth password for Sidekiq UI |

Generate a secure key:
```bash
openssl rand -hex 32
```

## Running tests

Initialize the test database (first time only):
```bash
docker compose exec -e RAILS_ENV=test web rails db:create db:schema:load
```

Run the test suite:
```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

Run with documentation format:
```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec --format documentation
```

## Code quality

```bash
docker compose exec web bundle exec rubocop
docker compose exec web bundle exec rubocop -A  # auto-fix correctable offenses
```

## Useful commands

```bash
# Rails console
docker compose exec web rails console

# View logs
docker compose logs -f web worker

# Restart services (picks up new .env values)
docker compose up -d

# Full rebuild (after Gemfile or Dockerfile changes)
docker compose build && docker compose up -d
```

## Running jobs manually

```bash
docker compose exec web rails runner "ChannelPollingJob.perform_now"
docker compose exec web rails runner "ProcessVideoJob.perform_later(video.id)"
```

## Sidekiq Web UI

Available at http://localhost:3000/sidekiq after startup. Shows queue depths, retries, and dead jobs. Login with `SIDEKIQ_WEB_USERNAME` / `SIDEKIQ_WEB_PASSWORD` from `.env`.
