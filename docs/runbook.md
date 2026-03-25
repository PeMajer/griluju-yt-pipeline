# Runbook — griluju-yt-pipeline

Operační postupy pro každodenní správu pipeline. Technická architektura je v [`architecture.md`](architecture.md).

---

## Přidání nového kanálu

### 1. Zjisti `channel_id`

YouTube kanály mají interní ID (`UC...`) které se liší od handle (`@ChannelHandle`). RSS feed funguje jen s ID.

```bash
docker compose exec web rails channels:resolve_id URL=https://www.youtube.com/@ChannelHandle
```

Nebo manuálně přes yt-dlp:
```bash
docker compose exec web yt-dlp --print channel_id "https://www.youtube.com/@ChannelHandle" --playlist-items 1
```

### 2. Vytvoř záznam v DB

```bash
docker compose exec web rails console
```

```ruby
YoutubeChannel.create!(
  name:             "Mad Scientist BBQ",
  channel_id:       "UCselvHbb5ah0sEqZrFa-7nA",
  channel_url:      "https://www.youtube.com/channel/UCselvHbb5ah0sEqZrFa-7nA",
  active:           true,
  default_language: "en",
  backfill_limit:   30    # kolik starých videí zpracovat zpětně
)
```

Při příštím polling cyklu (každých 6h) se kanál automaticky zpracuje a spustí backfill posledních `backfill_limit` videí.

### 3. Ruční trigger (volitelné)

```bash
docker compose exec worker rails runner "ChannelPollingJob.perform_now"
```

---

## Monitoring

### Sidekiq Web UI

http://localhost:3000/sidekiq — přehled front, retries, dead jobs.

Přihlášení: `SIDEKIQ_WEB_USERNAME` / `SIDEKIQ_WEB_PASSWORD` z `.env`.

### Stav videí v DB

```bash
docker compose exec web rails console
```

```ruby
# Přehled stavů
YoutubeVideo.group(:processing_status).count

# Čekají na přepis (stuck?)
YoutubeVideo.where(processing_status: "metadata_fetched")
            .where("updated_at < ?", 2.hours.ago)

# Selhala zpracování
YoutubeVideo.where(processing_status: "failed")
            .order(updated_at: :desc)
            .pluck(:youtube_video_id, :failed_reason, :retry_count)

# Přepisy připravené pro blog (nezpracované)
YoutubeVideo.where(processing_status: "transcript_ready", queued_for_blog: false).count
```

### Logy kontejnerů

```bash
docker compose logs -f web       # Rails app
docker compose logs -f worker    # Sidekiq
docker compose logs -f --tail=50 # Všechny služby, posledních 50 řádků
```

---

## Opravy a recovery

### Re-queue failed videí

```bash
# Všechna failed videa
docker compose exec web rails pipeline:retry_failed

# Filtrování per kanál
docker compose exec web rails pipeline:retry_failed CHANNEL=UCselvHbb5ah0sEqZrFa-7nA
```

### Ruční zpracování konkrétního videa

```bash
docker compose exec web rails runner "
  video = YoutubeVideo.find_by(youtube_video_id: 'VIDEO_ID')
  video.update!(processing_status: 'new')
  ProcessVideoJob.perform_later(video.id)
"
```

### Stuck videa (metadata_fetched bez dalšího postupu)

Sidekiq `ChannelPollingJob` má `recover_stuck_videos` — spouští se automaticky. Pokud potřebuješ ručně:

```bash
docker compose exec web rails runner "
  YoutubeVideo
    .where(processing_status: 'metadata_fetched')
    .where('updated_at < ?', 2.hours.ago)
    .find_each { |v| FetchTranscriptJob.perform_later(v.id) }
"
```

---

## Aktualizace yt-dlp

YouTube občas mění API — yt-dlp vyžaduje aktualizaci. Verze je fixovaná v `Dockerfile`:

```dockerfile
RUN /opt/pyenv/bin/pip install --no-cache-dir "yt-dlp==VERZE"
```

**Postup aktualizace:**
1. Zkontroluj [releases](https://github.com/yt-dlp/yt-dlp/releases) — přečti changelog
2. Aktualizuj verzi v `Dockerfile` i `Dockerfile.dev`
3. Rebuild image: `docker compose build && docker compose up -d`
4. Otestuj na jednom videu ručně

> Nikdy nepoužívej `yt-dlp` bez fixované verze (`pip install yt-dlp` bez `==VERZE`) — breakující změny přicházejí bez varování.

---

## Deaktivace kanálu

```bash
docker compose exec web rails console
```

```ruby
YoutubeChannel.find_by(channel_id: "UC...").update!(active: false)
```

Deaktivovaný kanál se přeskočí při pollingu. Existující videa zůstanou v DB.

---

## Restart služeb

```bash
# Restart všech kontejnerů (načte nové .env hodnoty)
docker compose up -d

# Restart pouze workera (např. po změně kódu jobu)
docker compose restart worker

# Kompletní rebuild (po změně Gemfile nebo Dockerfile)
docker compose build && docker compose up -d
```

---

## Produkční nasazení (Hetzner)

> Plánovaný přesun z OrbStack VM na Hetzner CX32 (4 vCPU, 8 GB RAM).

**Minimální požadavky:** CX32 — méně nestačí. Whisper model `medium` potřebuje ~4 GB RAM při přepisu.

Nasazení přes Kamal — konfigurace v `.kamal/`. Secrets jsou v `.kamal/secrets` (není v gitu).

### TODO: Kamal konfigurace (nedokončeno)

Kamal je přidán do projektu, ale **není nakonfigurován pro produkci**. Před nasazením na Hetzner je potřeba:

- [ ] Vytvořit server na Hetzner CX32 a zjistit IP adresu
- [ ] Vyplnit `config/deploy.yml` — server IP, Docker registry, service name
- [ ] Nastavit `.kamal/secrets` — registry password, `RAILS_MASTER_KEY`
- [ ] Přidat SSH klíč na server (`ssh-copy-id root@<server-ip>`)
- [ ] Otestovat: `kamal setup` → `kamal deploy`
- [ ] Nastavit ENV proměnné na serveru (viz `.env.example`): `YOUTUBE_API_KEY`, `BLOG_API_KEY`, atd.
- [ ] Ověřit, že Whisper model je stažen do Docker image (je v `Dockerfile`, ale ověřit na produkci)
- [ ] Nastavit cron / Sidekiq scheduler pro `ChannelPollingJob` (každých 6h)

```bash
kamal deploy
kamal logs
kamal shell     # SSH do kontejneru na serveru
```

---

## Blog integrace

Blog agent (projekt `griluju`) fetchuje přepisy přes API:

```bash
# Seznam nových přepisů
curl -H "X-Api-Key: $BLOG_API_KEY" \
  "http://localhost:3000/api/v1/videos?status=completed"

# Detail přepisu
curl -H "X-Api-Key: $BLOG_API_KEY" \
  "http://localhost:3000/api/v1/transcripts/VIDEO_ID"

# Označit jako zpracované blogem
curl -X PATCH \
  -H "X-Api-Key: $BLOG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"video": {"queued_for_blog": true}}' \
  "http://localhost:3000/api/v1/videos/VIDEO_ID"
```

Z prostředí `agent-sandbox` VM (blog agent) je pipeline dostupná na `http://192.168.139.146:3000`.
