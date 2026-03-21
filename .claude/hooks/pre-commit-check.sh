#!/bin/bash
# Claude Code PreToolUse hook — spustí se před každým git commit volaným Claudem
# Matcher v settings.json: "Bash(git commit*)"
# Provede mechanické kontroly: rubocop, pending migrace, security

set -uo pipefail

# Přečti (a zahoď) stdin — Claude Code hook vždy posílá JSON na stdin
cat > /dev/null

FAILED=0
OUTPUT=""

# --- 1. Rubocop (staged Ruby soubory) ---
RB_FILES=()
while IFS= read -r f; do [[ -n "$f" ]] && RB_FILES+=("$f"); done < <(git diff --cached --name-only 2>/dev/null | grep -E '\.(rb|rake)$' || true)

if [ ${#RB_FILES[@]} -gt 0 ]; then
    RUBOCOP_OUT=$(bundle exec rubocop --format simple "${RB_FILES[@]}" 2>&1 || true)
    if echo "$RUBOCOP_OUT" | grep -qE '^C:|^W:|^E:|^F:'; then
        OUTPUT+="❌ Rubocop offenses:\n$RUBOCOP_OUT\n\n"
        FAILED=1
    else
        OUTPUT+="✅ Rubocop OK\n"
    fi
else
    OUTPUT+="ℹ️  Rubocop — žádné Ruby soubory\n"
fi

# --- 2. Pending migrace ---
MIGRATION_STATUS=$(bundle exec rails db:migrate:status 2>/dev/null | grep '^\s*down' | head -5 || true)
if [ -n "$MIGRATION_STATUS" ]; then
    OUTPUT+="⚠️  Pending migrace (spusť rails db:migrate):\n$MIGRATION_STATUS\n\n"
    # Varování, ne blocker — migrace může být záměrně pending v branch
else
    OUTPUT+="✅ Migrace OK\n"
fi

# --- 3. Shell injection kontrola (staged Ruby soubory) ---
if [ ${#RB_FILES[@]} -gt 0 ]; then
    SHELL_INJECTION=$(git diff --cached -- '*.rb' 2>/dev/null | grep '^\+' | grep -E 'Open3\.(capture3|popen3)\s*\(' | grep -E '".*#\{|'\''.*#\{' || true)
    if [ -n "$SHELL_INJECTION" ]; then
        OUTPUT+="❌ SECURITY — možná shell injection (použij pole argumentů, ne string interpolaci):\n$SHELL_INJECTION\n\n"
        FAILED=1
    else
        OUTPUT+="✅ Shell injection kontrola OK\n"
    fi
fi

# --- 4. Hardcoded secrets kontrola ---
SECRETS=$(git diff --cached 2>/dev/null | grep '^\+' | grep -iE '(password|secret|api_key|token)\s*=\s*['\''"][^'\''"{][^'\''"{]{8,}' | grep -v 'ENV\[' | grep -v '_spec\.rb' || true)
if [ -n "$SECRETS" ]; then
    OUTPUT+="❌ SECURITY — možný hardcoded secret:\n$SECRETS\n\n"
    FAILED=1
else
    OUTPUT+="✅ Secrets kontrola OK\n"
fi

# --- 5. Docs reminder (staged soubory → příslušná dokumentace) ---
DOCS_HINTS=""
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      app/models/*)            DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Modely)\n" ;;
      app/jobs/*)              DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Jobs)\n" ;;
      app/services/youtube/*)  DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Services)\n" ;;
      app/services/blog/*)     DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Services)\n" ;;
      app/controllers/api/*)   DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce API)\n" ;;
      config/sidekiq.yml)      DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Sidekiq)\n" ;;
      docker-compose.yml|Dockerfile) DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Docker)\n" ;;
      lib/tasks/*)             DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Rake tasks)\n" ;;
      db/migrate/*)            DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Indexy)\n" ;;
      .claude/*)               DOCS_HINTS+="  $f → .claude/docs/architecture.md (sekce Agent workflow)\n" ;;
    esac
done < <(git diff --cached --name-only 2>/dev/null || true)

if [ -n "$DOCS_HINTS" ]; then
    OUTPUT+="ℹ️  Docs reminder — zkontroluj jestli je dokumentace aktuální:\n$DOCS_HINTS\n"
fi

# --- Výstup ---
echo -e "## Pre-commit hook výsledky\n\n${OUTPUT}"

if [ "$FAILED" -eq 1 ]; then
    echo -e "\n❌ Nalezeny problémy — commit zablokován. Oprav výše uvedené chyby."
    exit 2
fi

echo -e "\n✅ Všechny kontroly prošly."
exit 0
