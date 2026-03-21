# Lessons — griluju-yt-pipeline

Patterny z minulých korekcí a gotchas. Číst na začátku každé session.

---

<!-- Přidávej nové záznamy sem, nejnovější nahoře. Formát:
## Datum — krátký popis
Co se stalo a co z toho plyne.
-->

## 2026-03-21 — Ruby/Bundle setup na Ubuntu VM

Ruby je dostupné jako `ruby3.3`, bundle jako `bundle3.3`. Gemy jsou v `$HOME/.local/share/gem/ruby/3.3.0/`. Nutno nastavit `BUNDLE_PATH=$HOME/.local/share/gem/ruby/3.3.0` (v `~/.bundle/config`), jinak bundle hledá v system path a selhává. Při `rails new` se vygenerují soubory pro Kamal a Solid Queue/Cache — pro tento projekt nepotřebné, lze ignorovat nebo přidat do `.gitignore`.

## 2026-03-21 — shoulda-matchers validate_uniqueness_of vyžaduje subject s daty

`it { is_expected.to validate_uniqueness_of(:column) }` selže s `PG::NotNullViolation` pokud model má NOT NULL sloupce a subject je prázdný. Fix: `subject { create(:factory) }` vždy před uniqueness matchers.

## 2026-03-21 — VttCleaner regex — stripovat tagy, ne rejektovat řádky

Původní regex `.reject { |l| l =~ /...|<[^>]+>/ }` zahazoval celé řádky obsahující HTML tagy. YouTube VTT má inline tagy (`<c.colorXXX>text</c>`) — správně je `.map { |l| l.gsub(/<[^>]+>/, "") }` po rejectování strukturálních řádků.
