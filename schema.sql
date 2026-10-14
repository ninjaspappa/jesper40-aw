-- OSA-tabell för AW-padel 39+1
-- Kör detta i Supabase SQL Editor

create table if not exists guests (
  id text primary key,
  name text not null,
  invited boolean not null default false,
  rsvp text check (rsvp is null or rsvp in ('ja', 'nej', 'kanske')),
  arrival text,
  comment text,
  updated timestamptz,
  created_at timestamptz not null default now()
);

-- Tillåt alla att läsa och skriva (enkel OSA utan inloggning för gäster)
-- Admin skyddas med lösenord i frontend, inte via Supabase auth

alter table guests enable row level security;

create policy "Allow public read"
  on guests for select
  using (true);

create policy "Allow public insert"
  on guests for insert
  with check (true);

create policy "Allow public update"
  on guests for update
  using (true);

create policy "Allow public delete"
  on guests for delete
  using (true);

-- Seed: redan bjudna + ska bjudas
insert into guests (id, name, invited, rsvp) values
  ('1', 'Louise', true, null),
  ('2', 'Håkan', true, null),
  ('3', 'Johan Falk', true, null),
  ('4', 'Daniel Billing', true, null),
  ('5', 'Peter Aakvist', false, null),
  ('6', 'Morten Stark', false, null),
  ('7', 'Joaquin Samuelsson', false, null),
  ('8', 'Lisa Banks', false, null),
  ('9', 'Cecilia', false, null),
  ('10', 'Johan', false, null),
  ('11', 'Anton Kärf', false, null),
  ('12', 'Robert Slantesson', false, null),
  ('13', 'Jesper Lindgren', false, null),
  ('14', 'Christian Sivla', false, null),
  ('15', 'Christoffer Frejfelt', false, null)
on conflict (id) do nothing;
