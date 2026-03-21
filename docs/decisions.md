# Architectural Decisions

Key choices made during development and the reasoning behind them. Useful context before making changes that touch these areas.

---

## yt-dlp as the single YouTube interface

**Decision:** Use `yt-dlp` for everything YouTube-related — metadata, subtitles, audio download.

**Why:** No YouTube Data API key required, no quota limits, one actively maintained tool that handles all use cases. The YouTube API would require OAuth or API key management and has strict daily quotas.

**Trade-off:** yt-dlp is a scraper, not an official API. YouTube occasionally breaks it. Mitigated by pinning a specific version in the Dockerfile and updating deliberately.

---

## Fixed yt-dlp version in Dockerfile

**Decision:** `pip install yt-dlp==2026.03.17` instead of latest.

**Why:** YouTube changes its internal APIs frequently. When yt-dlp breaks, a new version fixes it — but it may also introduce breaking changes. Pinning the version means we know exactly when and why something stopped working.

**How to update:** Check [yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases), read the changelog, update the version in `Dockerfile` and `Dockerfile.dev` consciously.

---

## Deno as JS runtime for yt-dlp

**Decision:** Install Deno in the Docker image alongside yt-dlp.

**Why:** Since ~2025, YouTube requires JavaScript challenge solving that yt-dlp cannot handle with Python alone. Deno is the recommended external JS runtime. Without it, yt-dlp cannot access YouTube at all. The `yt-dlp-ejs` package bridges yt-dlp and Deno.

---

## Whisper model pre-downloaded at build time

**Decision:** Download the Whisper `medium` model during `docker build`, not at runtime.

**Why:** The model is ~1.5 GB. Downloading it on first job run would cause a timeout (Sidekiq job timeout) or OOM kill on low-memory machines. Building it into the image means cold starts are instant.

**Trade-off:** Image is larger and first build takes 5–10 minutes. Acceptable for an infrequently rebuilt internal tool.

---

## Three-tier transcript fallback

**Decision:** Try subtitles in this order: manual → Whisper → auto-captions.

**Why:**
- Manual subtitles: highest quality, accurate timing, no compute cost
- Whisper local: high quality for channels without subtitles, works offline
- Auto-captions: lowest quality (rolling/overlapping format), but better than nothing

This order maximizes transcript quality while minimizing Whisper compute time.

---

## VTT rolling caption deduplication

**Decision:** Implement sliding-window suffix-prefix overlap detection in `VttCleanerService`.

**Why:** YouTube auto-captions use a rolling format — each VTT block overlaps with the previous one by several words. Naive concatenation produces `"smoke the brisket low low and slow for slow for twelve hours"`. The `longest_suffix_prefix_overlap` algorithm merges blocks correctly.

---

## Blog pulls transcripts, pipeline does not push

**Decision:** The blog agent fetches transcripts via `GET /api/v1/transcripts/:video_id` on demand. The pipeline does not send webhooks or push data.

**Why:** The blog is a Next.js static export on Cloudflare Pages — it cannot receive HTTP webhooks (no server-side runtime). The blog agent (Claude Code in `agent-sandbox` VM) polls the pipeline API when processing new transcripts.

**API access:** Blog agent runs in OrbStack `agent-sandbox` VM, reaches pipeline at `http://192.168.139.146:3000`. If the server IP changes, update `PIPELINE_BASE_URL` in the blog project's `.env.local`.

---

## Sidekiq concurrency limits per queue

**Decision:**
- `yt_dlp` queue: max 3 concurrent workers
- `whisper` queue: max 1 concurrent worker

**Why:**
- `yt_dlp`: YouTube rate-limits aggressive scrapers. 3 concurrent requests stay below the threshold while keeping throughput acceptable.
- `whisper`: Whisper `medium` requires ~4 GB RAM per inference. Running two simultaneously on an 8 GB machine (Hetzner CX32) causes OOM kill.

---

## connection_pool pinned to ~> 2.4

**Decision:** `gem "connection_pool", "~> 2.4"` in Gemfile instead of latest.

**Why:** `connection_pool 3.0.x` changed the `TimedStack#pop` method signature in a way incompatible with Sidekiq 7.3.x. The combination caused `sidekiq-cron` scheduler to crash on startup with `ArgumentError: wrong number of arguments`. Pinning to 2.x avoids this until Sidekiq ships a fix.

**When to revisit:** After upgrading Sidekiq to a version that explicitly supports connection_pool 3.x.
