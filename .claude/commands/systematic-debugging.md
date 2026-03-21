Hloubkové debugování — najdi root cause před tím, než cokoliv opravíš.

Spouštěj když: oprava nefunguje napoprvé, nebo chyba není jasně pochopená.

## Fáze 1 — Root cause investigation

Nespěchej na opravu. Nejdřív pochop problém.

```bash
# Co se nedávno změnilo?
git log -10 --oneline

# Logy z kontejnerů
docker compose logs --tail=100 web
docker compose logs --tail=100 worker

# Sidekiq dead joby
docker compose exec worker bundle exec rails runner \
  "Sidekiq::DeadSet.new.first(5).each{|j| puts j.item.inspect}"
```

Přečti chybovou hlášku **celou** — nespoléhej na první řádek. Stack trace ukazuje kde problém leží.

Pro vícevrstvé chyby (Sidekiq job → service → yt-dlp) vytipuj kde přesně selhává:
- Selžuje samotné yt-dlp volání (ověř manuálně `docker compose exec worker yt-dlp ...`)?
- Je chyba v Ruby kódu (parsing výstupu, datový typ)?
- Je chyba v databázi (constraint, missing index)?
- Je to race condition (dva workery zpracovávají stejné video)?

## Fáze 2 — Pattern analysis

Najdi fungující příklad podobné věci v kódu:

```bash
# Najdi obdobný job nebo service
grep -rn 'Open3.capture3' app/ --include="*.rb" | head -20

# Najdi podobný ensure blok
grep -rn 'FileUtils.rm_f' app/ --include="*.rb" | head -20

# Zkontroluj processing_status distribuce
docker compose exec worker bundle exec rails runner \
  "puts YoutubeVideo.group(:processing_status).count"
```

Porovnej fungující příklad s nefungujícím. Identifikuj konkrétní rozdíl.

## Fáze 3 — Hypotéza a ověření

Formuluj jednu konkrétní hypotézu: _"Problém je v X, protože Y."_

Udělej **jednu** minimální změnu. Neopravuj víc věcí naráz — pak nevíš co pomohlo.

Ověř:
```bash
bundle exec rspec spec/path/to/relevant_spec.rb
# nebo
docker compose exec worker bundle exec rails runner "..."
```

## Fáze 4 — Stop pravidlo

**Pokud 3 nebo více pokusů o opravu selhalo → STOP.**

Nepokračuj ve flickování symptomů. Místo toho:
1. Přehodnoť základní předpoklady — je problém tam kde si myslíš?
2. Zkontroluj zda problém není v konfiguraci (Sidekiq concurrency, Docker networking, ENV proměnné)
3. Zkontroluj zda yt-dlp verze stále funguje s YouTube (`yt-dlp --version` a test stažení)
4. Přečti `.claude/docs/architecture.md` nebo `.claude/docs/lessons.md` od začátku — možná tam je odpověď

Toto pravidlo existuje protože po 3 neúspěšných pokusech je velmi pravděpodobné, že řešíš špatný problém nebo na špatném místě.
