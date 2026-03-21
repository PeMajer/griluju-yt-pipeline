Uzavři aktuální pracovní sezení — zkontroluj stav práce, uncommitted změny a ulož kontext pro příště.

## Postup

### 1. Stav repozitáře

```bash
git status
git diff --stat HEAD
git log main..HEAD --oneline
```

### 2. Uncommitted změny

Pokud existují uncommitted změny:
- Jsou hotové a otestované? → nabídni `/review` + commit
- Jsou rozdělaná práce? → ulož do paměti co zbývá dokončit
- Jsou experimentální? → upozorni, navrhni `git stash`

### 3. Dokončení větve (pokud jsou commity nad main)

Pokud `git log main..HEAD` ukazuje commity, nabídni přesně tyto 4 možnosti:

```
Co udělat s větví?

1. Push + otevřít Pull Request
2. Ponechat větev — pokračovat příště
3. Merge do main (lokálně)
4. Zahodit větev (smazat)
```

**Nikdy neprováděj akci bez explicitního výběru uživatele.**

Pro možnost 4 (zahodit) vyžaduj potvrzení napsáním slova `zahodit`.
Spusť `/review` před merge nebo PR (možnosti 1 a 3).

### 4. Stav pipeline (pokud aplikace běží)

```bash
# Sidekiq fronta — čekající joby
docker compose exec worker bundle exec rails runner "puts Sidekiq::Queue.all.map{|q| \"#{q.name}: #{q.size}\"}"

# Videa ve stavu failed
docker compose exec worker bundle exec rails runner "puts YoutubeVideo.where(processing_status: 'failed').count"
```

Pokud jsou failed videa → upozorni. Nenechávej sezení otevřené s uvízlými joby.

### 5. Shrnutí sezení

Vypiš stručné shrnutí:

```
## Sezení — shrnutí

### Dokončeno
- [co bylo dokončeno]

### Nedokončeno / příště
- [co zbývá, s kontextem proč]

### Důležité poznatky
- [co by bylo dobré si pamatovat pro příští sezení]
```

### 6. Aktualizace lessons.md

Pokud bylo odhaleno nové gotcha, technický problém nebo korekce od uživatele → přidej do `.claude/docs/lessons.md`.

Neukládej: hotovou práci, věci které jsou v kódu nebo git historii.
