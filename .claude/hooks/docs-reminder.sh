#!/usr/bin/env bash
# PostToolUse hook: after editing a relevant file, inject a docs-update reminder
# into Claude's context so it knows which doc to check/update.

INPUT=$(cat)
FILE=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('file_path',''))" <<< "$INPUT" 2>/dev/null)

[[ -z "$FILE" ]] && exit 0

DOC=""
REASON=""

case "$FILE" in
  app/models/*)
    DOC=".claude/docs/architecture.md — sekce Modely"
    REASON="model schema or associations changed"
    ;;
  app/jobs/*)
    DOC=".claude/docs/architecture.md — sekce Jobs a stavový automat"
    REASON="job logic or retry strategy changed"
    ;;
  app/services/youtube/*)
    DOC=".claude/docs/architecture.md — sekce Services"
    REASON="YouTube service changed"
    ;;
  app/services/blog/*)
    DOC=".claude/docs/architecture.md — sekce Services"
    REASON="blog service changed (VttCleaner, WebhookService)"
    ;;
  app/controllers/api/*)
    DOC=".claude/docs/architecture.md — sekce API"
    REASON="API endpoint changed"
    ;;
  config/sidekiq.yml)
    DOC=".claude/docs/architecture.md — sekce Sidekiq konfigurace"
    REASON="Sidekiq config changed (queues, concurrency)"
    ;;
  docker-compose.yml|Dockerfile)
    DOC=".claude/docs/architecture.md — sekce Docker Compose"
    REASON="Docker setup changed"
    ;;
  lib/tasks/*)
    DOC=".claude/docs/architecture.md — sekce Rake tasks"
    REASON="rake task changed"
    ;;
  db/migrate/*)
    DOC=".claude/docs/architecture.md — sekce Databázové indexy"
    REASON="migration added — check if indexes are complete"
    ;;
  .claude/hooks/*|.claude/settings.json)
    DOC=".claude/docs/architecture.md — sekce Agent workflow"
    REASON="Claude hooks or settings changed"
    ;;
  *)
    exit 0
    ;;
esac

echo "Docs reminder: edited '$FILE' ($REASON) — check if $DOC needs updating."
exit 0
