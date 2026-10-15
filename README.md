# AW-padel – 39 + 1 (OSA)

Enkel, mobilanpassad OSA-sida för Jesper's 40-årsfest med AW-padel.

## Live

- **Offentlig:** https://jesper40-aw.vercel.app
- **Admin:** https://jesper40-aw.vercel.app/#admin
  Lösenordet ligger inte i repot (repot är publikt). Det kontrolleras i databasen.

## Lagring

OSA:erna sparas i **Supabase**, i projektet *porty*, i ett eget schema `jesper40`
så att det inte krockar med porty. Sidan pratar direkt med Supabase via
`public.jesper40_*`-funktionerna; tabellerna går inte att nå direkt via API:t.

- Gäster kan bara skicka in sin egen OSA (ett namn som redan finns uppdateras).
- Admin (lista, lägga till, markera bjuden, ta bort, CSV) kräver lösenordet.
- "Ta bort" döljer gästen i stället för att radera, så det går att ångra.

Byta lösenord och ångra en borttagning: se kommentarerna sist i `schema.sql`.

## Filer

- `index.html` – hela appen (offentlig OSA + admin)
- `schema.sql` – schema, funktioner och seed-data, exakt som det ligger i Supabase

## Gästlista (seed)

**Redan bjudna:** Louise, Håkan, Johan Falk, Daniel Billing

**Ska bjudas:** Peter Aakvist, Morten Stark, Joaquin Samuelsson, Lisa Banks, Cecilia, Johan, Anton Kärf, Robert Slantesson, Jesper Lindgren, Christian Sivla, Christoffer Frejfelt
