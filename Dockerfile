# Produkční Dockerfile — pre-download Whisper model medium (Varianta A)
# Build: docker build -t griluju-yt-pipeline .

FROM ruby:3.3-slim AS base

WORKDIR /app

# Systémové závislosti
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      libpq-dev \
      libyaml-dev \
      ffmpeg \
      python3 \
      python3-venv \
      curl \
      unzip \
      git \
      postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Deno v2.2.3 — povinný JS runtime pro yt-dlp (YouTube JS výzvy od ~2025)
RUN ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/aarch64/aarch64/') && \
    curl -fsSL "https://github.com/denoland/deno/releases/download/v2.2.3/deno-${ARCH}-unknown-linux-gnu.zip" \
      -o /tmp/deno.zip && \
    unzip /tmp/deno.zip -d /usr/local/bin/ && \
    rm /tmp/deno.zip && \
    deno --version

# Python venv + yt-dlp (fixovaná verze) + Deno bridge + Whisper
RUN python3 -m venv /opt/pyenv && \
    /opt/pyenv/bin/pip install --no-cache-dir \
      "yt-dlp==2026.3.17" \
      yt-dlp-ejs \
      "whisper-ctranslate2==0.4.4"

ENV PATH="/opt/pyenv/bin:/usr/local/bin:$PATH"

# Pre-download Whisper model medium při build time → žádný cold start, žádný timeout
# Model ~1.5 GB — bez toho by se stahoval za runtime → OOM / timeout
RUN python3 -c "from faster_whisper import WhisperModel; WhisperModel('medium', download_root='/opt/whisper_models')"
ENV WHISPER_MODEL_PATH=/opt/whisper_models

# Adresář pro dočasné Whisper výstupy (VTT, MP3)
RUN mkdir -p /tmp/whisper

# Gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test && \
    rm -rf ~/.bundle/cache

COPY . .

RUN bundle exec bootsnap precompile app/ lib/

ENV RAILS_ENV=production
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
