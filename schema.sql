-- OSA-databas för AW-padel 39+1
--
-- Ligger i Supabase-projektet "porty", i ett eget schema (jesper40) så att
-- den inte krockar med porty. Schemat exponeras inte i API:t och anon har
-- inga rättigheter på det: sidan når datan bara via public.jesper40_*-
-- funktionerna nedan, som körs med ägarens rättigheter.
--
-- Gäster kan bara skicka in sin egen OSA. Allt annat (läsa listan, lägga
-- till, ta bort) kräver adminlösenordet, som kontrolleras här i databasen
-- och aldrig ligger i sidans källkod.
--
-- "Ta bort" i admin döljer gästen (removed = true) i stället för att radera,
-- så att en felklickad borttagning går att ångra.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists jesper40;

create table jesper40.guests (
  id bigint generated always as identity primary key,
  name text not null check (length(name) between 1 and 100),
  invited boolean not null default false,
  rsvp text check (rsvp in ('ja', 'nej', 'kanske')),
  arrival text,
  comment text check (length(comment) <= 1000),
  updated timestamptz,
  created_at timestamptz not null default now(),
  removed boolean not null default false
);

-- En OSA under ett namn som redan finns uppdaterar den raden, oavsett versaler.
create unique index guests_name_key on jesper40.guests (lower(name));

create table jesper40.admin (
  id boolean primary key default true check (id),
  password_hash text not null
);

alter table jesper40.guests enable row level security;
alter table jesper40.admin enable row level security;

create function jesper40.require_admin(p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from jesper40.admin a
    where a.password_hash = extensions.crypt(p_password, a.password_hash)
  ) then
    raise exception 'Fel lösenord' using errcode = '28P01';
  end if;
end;
$$;

-- Publik: gästens OSA.
create function public.jesper40_submit_rsvp(p_name text, p_rsvp text, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(p_name);
begin
  if v_name is null or v_name = '' then
    raise exception 'Namn saknas' using errcode = '22023';
  end if;
  if p_rsvp is null or p_rsvp not in ('ja', 'nej', 'kanske') then
    raise exception 'Ogiltigt svar' using errcode = '22023';
  end if;

  insert into jesper40.guests (name, rsvp, comment, updated)
  values (v_name, p_rsvp, nullif(btrim(p_comment), ''), now())
  on conflict ((lower(name))) do update
    set rsvp = excluded.rsvp,
        -- Ett nytt svar utan kommentar behåller den gamla (t.ex. allergier).
        comment = coalesce(excluded.comment, guests.comment),
        arrival = null,
        updated = excluded.updated,
        removed = false;
end;
$$;

-- Admin: allt nedan kräver lösenordet.
create function public.jesper40_admin_guests(p_password text)
returns table (
  id bigint,
  name text,
  invited boolean,
  rsvp text,
  arrival text,
  comment text,
  updated timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  return query
    select g.id, g.name, g.invited, g.rsvp, g.arrival, g.comment, g.updated
    from jesper40.guests g
    where not g.removed;
end;
$$;

create function public.jesper40_admin_add_guest(p_password text, p_name text, p_invited boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  insert into jesper40.guests (name, invited) values (btrim(p_name), coalesce(p_invited, false))
  on conflict ((lower(name))) do update
    set invited = excluded.invited,
        removed = false;
end;
$$;

create function public.jesper40_admin_set_invited(p_password text, p_id bigint, p_invited boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  update jesper40.guests set invited = p_invited where id = p_id;
end;
$$;

create function public.jesper40_admin_remove_guest(p_password text, p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  update jesper40.guests set removed = true where id = p_id;
end;
$$;

-- Avstängd: en lösenordsfri gästlista prövades och stängdes av direkt, så
-- att gästernas namn och kommentarer inte går att läsa utan lösenord.
create function public.jesper40_guest_overview()
returns table (
  id bigint,
  name text,
  invited boolean,
  rsvp text,
  arrival text,
  comment text,
  updated timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  raise exception 'Avstängd: gästlistan kräver lösenord' using errcode = '28P01';
end;
$$;

-- Seed: redan bjudna + ska bjudas
insert into jesper40.guests (name, invited) values
  ('Louise', true),
  ('Håkan', true),
  ('Johan Falk', true),
  ('Daniel Billing', true),
  ('Peter Aakvist', false),
  ('Morten Stark', false),
  ('Joaquin Samuelsson', false),
  ('Lisa Banks', false),
  ('Cecilia', false),
  ('Johan', false),
  ('Anton Kärf', false),
  ('Robert Slantesson', false),
  ('Jesper Lindgren', false),
  ('Christian Sivla', false),
  ('Christoffer Frejfelt', false)
on conflict do nothing;

-- Sätt eller byt adminlösenordet (kör i SQL Editor, checka inte in lösenordet):
--   insert into jesper40.admin (password_hash)
--   values (extensions.crypt('DITT-LÖSENORD', extensions.gen_salt('bf')))
--   on conflict (id) do update set password_hash = excluded.password_hash;
--
-- Ångra en borttagning:
--   update jesper40.guests set removed = false where name = 'Namn';
