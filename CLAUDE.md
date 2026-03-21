# griluju-yt-pipeline

Interní nástroj pro blog o grilování — automaticky sleduje zahraniční YouTube kanály, detekuje nová videa, získává přepisy a notifikuje blog přes webhook. Pipeline je čistě sběrný a přípravný nástroj; AI analýza (psaní článků, tone of voice) probíhá výhradně na straně blogu.

Provoz: **lokálně v OrbStack VM** (`griluju-yt`), výhledově přesun na **Hetzner CX32**.

## Stack

- **Ruby on Rails** — hlavní aplikace
- **PostgreSQL** — databáze
- **Sidekiq + Redis** — background joby
- **yt-dlp** — stahování metadat a titulků z YouTube
- **whisper-ctranslate2** — lokální speech-to-text pro videa bez titulků
- **Docker Compose** — celý stack v kontejnerech

## Detailed docs

- **Architektura & stack:** `docs/architecture.md`
- **Pipeline plán (reference):** `docs/pipeline-plan.md`
- **Lessons:** `docs/lessons.md`

## Dokumentace (plná reference)

| Soubor | Obsah |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Stack, Docker setup, modely, jobs, API, indexy |
| [docs/pipeline-plan.md](docs/pipeline-plan.md) | Kompletní plán BBQ pipeline (v13) — referenční dokument |
| [docs/lessons.md](docs/lessons.md) | Patterny z minulých korekcí — číst na začátku session |

---

## Skills — kdy je použít

- **`/review`** — před každým commitem (rubocop + migrace + bezpečnostní kontroly)
- **`/session-end`** — uzavření sezení (stav, uncommitted změny, kontext pro příště)
- **`/systematic-debugging`** — když oprava nefunguje napoprvé; 4-fázový protokol s hard stop po 3 pokusech

---

## Hranice — co agent smí a nesmí

✅ **Always safe:** Čtení souborů, spouštění testů/rubocop, prohledávání kódu, editace kódu

⚠️ **Ask first:**
- Task vyžaduje smazání nebo zásadní restrukturalizaci existujících souborů
- Existují 2+ validní architektonické přístupy s reálnými trade-offs
- Instrukce je v rozporu s CLAUDE.md nebo pipeline plánem
- Chybí závislost nebo ENV proměnná
- Databázová migrace mění existující sloupce nebo maže data

🚫 **Never:**
- Nikdy nepushuj přímo do `main` — vždy branch + PR
- Nikdy necommituj s failing testy nebo rubocop chybami
- Nikdy nespouštěj yt-dlp joby paralelně více než 3 najednou (rate limit)
- Nikdy nespouštěj více než 1 Whisper job najednou (OOM)
- Nikdy nesmazej dočasné soubory (audio MP3, VTT) bez `ensure` bloku
- Nikdy nepoužívej `shell: true` nebo string interpolaci v Open3 volání (shell injection)
- Nikdy nepište "Jako jazykový model AI..."

---

## Git — workflow pro každý úkol

1. Zjisti aktuální branch: `git branch --show-current`
2. Pokud `main` → vždy nová branch. Feature branch → porovnej s existujícími změnami.
3. Nová branch: `git checkout main && git pull origin main && git checkout -b [type/popis]`
4. Naming: `feature/`, `fix/`, `chore/`
5. Implementuj → `/review` → commit → push → `gh pr create`

IMPORTANT: Commit messages v češtině, stručné. Vždy volej `git add` a `git commit` jako **dvě samostatná volání** — nikdy nespojuj `&&`. Pre-commit hook se spustí pouze pokud příkaz začíná `git commit`.

---

## Dokumentace

Když měníš kód, zkontroluj jestli existuje relevantní dokumentace v `.claude/docs/` která ho popisuje. Pokud ano, aktualizuj ji. Nenechávej docs out of sync s kódem.

---

## Self-review před dokončením

1. Najdi VŠECHNA místa, která závisí na tom co jsi změnil.
2. Spusť `/review` — rubocop, testy, migrační kontroly.
3. Projdi git diff jako celek před tím než prohlásíš hotovo.
4. Zeptej se sám sebe: **"Schválil by to zkušený Rails developer?"** Pokud ne, oprav to.

**Evidence first** — nikdy neříkej "should work", "pravděpodobně projde" nebo "zdá se OK" bez spuštění příkazu a přečtení výstupu. Hotovo znamená zelený output.
