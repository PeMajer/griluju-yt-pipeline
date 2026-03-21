Zkontroluj aktuální změny před commitem — rubocop, testy a migrační pravidla.

## Postup

### 1. Zjisti rozsah změn

```bash
git diff --name-only HEAD
git diff --stat HEAD
```

Pokud nejsou žádné změny, vypiš to a skonči.

### 2. Rubocop

```bash
bundle exec rubocop --format simple
```

Pokud jsou offenses → oprav auto-opravitelné (`rubocop -A`), zbytek oprav ručně. Necommituj s rubocop chybami.

### 3. Testy

```bash
bundle exec rspec --format progress
```

Pokud testy selhávají → oprav před pokračováním. Necommituj s failing testy.

### 4. Migrační kontroly (pokud jsou změny v `db/`)

Pokud byly přidány nebo upraveny soubory v `db/migrate/`:

- **Nové indexy** — jsou všechny dotazy pokryté indexem? (viz architecture.md — sekce Indexy)
- **Composite indexy** — `[:processing_status, :webhook_sent_at]` a `[:processing_status, :updated_at]` jsou povinné
- **Destructive operace** — `remove_column`, `drop_table` vyžadují potvrzení od uživatele
- **Schema.rb** — je aktuální? (`bundle exec rails db:migrate` a zkontroluj `git diff db/schema.rb`)

### 5. Bezpečnostní kontroly (pro Ruby soubory)

Projdi diff (`git diff HEAD`) a zkontroluj:

- **Shell injection** — všechna volání yt-dlp a whisper používají `Open3.capture3` s polem argumentů (ne string interpolaci)
- **Dočasné soubory** — každé stahování audio/VTT souborů má `ensure` blok s `FileUtils.rm_f`
- **ENV proměnné** — žádné secrets hardcoded v kódu; vše přes `ENV['...']`
- **API autentizace** — každý API endpoint ověřuje `X-Api-Key` hlavičku

### 6. Kvalita kódu (pro Ruby soubory)

Projdi diff a zhodnoť:

- **Sidekiq limity** — yt-dlp fronta max 3 concurrent workers, whisper fronta max 1
- **Retry blok** — každý job má `rescue StandardError` s `video&.increment!(:retry_count)` a `raise`
- **Idempotence** — každý job má guard který zabrání duplikátnímu zpracování
- **Duplicita** — vznikl kód podobný existujícímu? Lze extrahovat do service?

### 7. Dokumentace

Teprve když je kód finální (rubocop OK, testy OK, bezpečnost OK), zkontroluj dokumentaci:

```bash
grep -r "<název_třídy_nebo_metody>" docs/ --include="*.md" -l
```

Mapování co dokumentovat kde:

| Změna | Dokumentace |
|---|---|
| `app/models/**` | `docs/architecture.md` — sekce Modely |
| `app/jobs/**` | `docs/architecture.md` — sekce Jobs a stavový automat |
| `app/services/**` | `docs/architecture.md` — sekce Services |
| `app/controllers/api/**` | `docs/architecture.md` — sekce API |
| `config/sidekiq.yml` | `docs/architecture.md` — sekce Sidekiq |
| `docker-compose.yml` nebo `Dockerfile` | `docs/architecture.md` — sekce Docker |
| `lib/tasks/**` | `docs/architecture.md` — sekce Rake tasks |
| `.claude/` | `docs/architecture.md` — sekce Agent workflow |

### 8. Shrnutí

Vypiš přehledný report:

```
## Review výsledky

### Rubocop
✅ Bez offenses  |  ❌ Opraveno: ...

### Testy
✅ Prošly  |  ❌ Selhalo: ...

### Migrace
✅ OK  |  ⚠️ Upozornění: ...

### Bezpečnost
✅ OK  |  ⚠️ Upozornění: ...

### Kvalita kódu
✅ Bez připomínek  |  ⚠️ Návrhy: ...

### Dokumentace
✅ Aktuální  |  ⚠️ Aktualizováno: ...

### Závěr
✅ Připraveno k commitu  |  ❌ Nutno opravit
```

> `git add` a `git commit` volej vždy jako **dvě samostatná volání** — nikdy nespojuj `&&`. Pre-commit hook se spustí pouze pokud příkaz začíná `git commit`.
