# AW-padel – 39 + 1 (OSA)

Mobilanpassad OSA-sida för Jespers 40-årsfest med AW-padel, fredag 4 december
2026 kl. 17–20 på Nordic Frillesås.

## Live

- **OSA-sidan:** https://jesper40-aw.vercel.app
- **Admin:** tryck på "AW-padel 2026" längst ner på sidan (eller gå till
  https://jesper40-aw.vercel.app/#admin). Logga in en gång per enhet; inloggningen
  sparas tills du trycker "Logga ut". Lösenordet ligger i databasen, inte i repot.

`main` deployas automatiskt till produktion av Vercel.

## Admin: två separata listor

- **OSA** – de riktiga svaren från gästerna (Ja/Kanske/Nej, ankomst,
  kommentar). Ett svar kan döljas; det ligger kvar i databasen och kan tas
  fram igen.
- **Inbjudna** – din egen avbockningslista. Lägg till namn och bocka av när
  du har bjudit in någon. Listan har ingen koppling till OSA:erna.

Båda listorna kan laddas ner som CSV (öppnas direkt i svensk Excel).

## Lagring

Datan ligger i **Supabase**, i projektet *porty*, i ett eget schema
`jesper40` så att det inte krockar med porty. Sidan pratar direkt med
Supabase via `public.jesper40_*`-funktionerna; tabellerna går inte att nå
direkt via API:t.

- Gäster kan bara skicka in sin egen OSA. Svarar någon igen med samma namn
  uppdateras svaret, och sidan säger till om namnet redan hade ett svar.
- Allt i admin kräver lösenordet.
- Varje inskick loggas i `jesper40.rsvp_log`, så ett överskrivet svar går
  att hitta igen.

Byta lösenord, ta fram en dold OSA m.m.: se slutet av `schema.sql`.

## Filer

- `index.html` – hela appen (publik OSA + admin), ingen byggprocess
- `aw-padel-39plus1.ics` – kalenderfilen bakom "Kalender"-knappen
- `og.png`, `favicon.svg`, `apple-touch-icon.png` – delningsbild och ikoner
- `vercel.json` – säkerhetsheaders och noindex
- `schema.sql` – schema och funktioner, som det ligger i produktion
- `migrations/` – ändringar i databasen, i den ordning de körts

`README.md`, `schema.sql` och `migrations/` publiceras inte på sajten (se
`.vercelignore`).

## Testa lokalt

```bash
python3 -m http.server 5173
```

Öppna http://localhost:5173. Sidan pratar med den riktiga databasen, så
ta bort eventuella test-OSA:er efteråt.
