# AW-padel – 39 + 1 (OSA)

Enkel, mobilanpassad OSA-sida för Jesper's 40-årsfest med AW-padel.

## Live

- **Offentlig:** https://jesper40-aw.vercel.app
- **Admin:** https://jesper40-aw.vercel.app/#admin  
  Lösenord: `padel40admin`

## Nuvarande lagring

Just nu används `localStorage` (per webbläsare). För permanent lagring: koppla **Supabase**.

## Supabase-setup

1. Skapa projekt på [supabase.com](https://supabase.com)
2. Kör SQL i `schema.sql` (SQL Editor)
3. Kopiera **Project URL** + **anon key** (Settings → API)
4. Uppdatera sidan att använda Supabase istället för localStorage

## Filer

- `index.html` – hela appen (offentlig OSA + admin)
- `schema.sql` – tabell + RLS + seed-data

## Gästlista (seed)

**Redan bjudna:** Louise, Håkan, Johan Falk, Daniel Billing  

**Ska bjudas:** Peter Aakvist, Morten Stark, Joaquin Samuelsson, Lisa Banks, Cecilia, Johan, Anton Kärf, Robert Slantesson, Jesper Lindgren, Christian Sivla, Christoffer Frejfelt
