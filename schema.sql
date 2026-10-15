-- OSA-databas för AW-padel 39+1
--
-- Ligger i Supabase-projektet "porty", i ett eget schema (jesper40) så att
-- den inte krockar med porty. Schemat exponeras inte i API:t och anon har
-- inga rättigheter på det: sidan når datan bara via public.jesper40_*-
-- funktionerna nedan, som körs med ägarens rättigheter.
--
-- Två separata listor som inte matchas mot varandra:
--   jesper40.guests   "OSA": de riktiga svaren från gästerna
--   jesper40.invites  "Inbjudna": Jespers egen avbockningslista
--
-- Gäster kan bara skicka in sin egen OSA. Allt annat (läsa listorna, lägga
-- till, bocka av, ta bort) kräver adminlösenordet, som kontrolleras här i
-- databasen och aldrig ligger i sidans källkod.
--
-- "Dölj" på en OSA sätter removed = true i stället för att radera, så att
-- en felklickad borttagning går att ångra. Varje inskick loggas dessutom i
-- jesper40.rsvp_log, så ett överskrivet svar går att hitta igen.
--
-- Den här filen beskriver läget i produktion. Ändringar görs som nya filer
-- i migrations/ och förs sedan in här.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists jesper40;

-- ---------- Tabeller ----------

create table jesper40.guests (
  id bigint generated always as identity primary key,
  name text not null check (length(name) between 1 and 100),
  rsvp text check (rsvp in ('ja', 'nej', 'kanske')),
  arrival text constraint guests_arrival_check check (arrival in ('start', 'senare')),
  comment text check (length(comment) <= 1000),
  updated timestamptz,
  created_at timestamptz not null default now(),
  removed boolean not null default false
);

-- En OSA under ett namn som redan finns uppdaterar den raden, oavsett versaler.
create unique index guests_name_key on jesper40.guests (lower(name));

create table jesper40.invites (
  id bigint generated always as identity primary key,
  name text not null check (length(name) between 1 and 100),
  invited boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index invites_name_key on jesper40.invites (lower(name));

create table jesper40.rsvp_log (
  id bigint generated always as identity primary key,
  name text not null,
  rsvp text not null,
  arrival text,
  comment text,
  created_at timestamptz not null default now()
);

create table jesper40.admin (
  id boolean primary key default true check (id),
  password_hash text not null
);

alter table jesper40.guests enable row level security;
alter table jesper40.invites enable row level security;
alter table jesper40.rsvp_log enable row level security;
alter table jesper40.admin enable row level security;

-- ---------- Interna hjälpfunktioner ----------

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

-- Blanktecken (även hårda mellanslag) slås ihop till ett mellanslag och trimmas.
create function jesper40.clean_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), '')
$$;

-- ---------- Publikt ----------

-- Gästens OSA. Returnerar 'created' eller 'updated' så att sidan kan säga
-- till om någon redan svarat under samma namn.
create function public.jesper40_submit_rsvp(
  p_name text,
  p_rsvp text,
  p_comment text default null,
  p_arrival text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := jesper40.clean_name(p_name);
  v_comment text := nullif(btrim(p_comment), '');
  v_arrival text := case when p_rsvp = 'nej' then null else nullif(btrim(p_arrival), '') end;
  v_prev text;
begin
  if v_name is null then
    raise exception 'Skriv ditt namn.' using errcode = '22023';
  end if;
  if length(v_name) > 100 then
    raise exception 'Namnet är för långt (max 100 tecken).' using errcode = '22023';
  end if;
  if p_rsvp is null or p_rsvp not in ('ja', 'nej', 'kanske') then
    raise exception 'Välj Ja, Kanske eller Nej.' using errcode = '22023';
  end if;
  if length(v_comment) > 1000 then
    raise exception 'Kommentaren är för lång (max 1000 tecken).' using errcode = '22023';
  end if;
  if v_arrival is not null and v_arrival not in ('start', 'senare') then
    raise exception 'Ogiltig ankomsttid.' using errcode = '22023';
  end if;

  select g.rsvp into v_prev from jesper40.guests g where lower(g.name) = lower(v_name);
  -- Tak mot spam: ett privat event behöver inte fler än så här.
  if not found and (select count(*) from jesper40.guests) >= 300 then
    raise exception 'OSA-listan är full – hör av dig direkt i stället.' using errcode = '54000';
  end if;

  insert into jesper40.guests (name, rsvp, comment, arrival, updated)
  values (v_name, p_rsvp, v_comment, v_arrival, now())
  on conflict ((lower(name))) do update
    set rsvp = excluded.rsvp,
        -- Ett nytt svar utan kommentar behåller den gamla (t.ex. allergier).
        comment = coalesce(excluded.comment, guests.comment),
        arrival = excluded.arrival,
        updated = excluded.updated,
        removed = false;

  if (select count(*) from jesper40.rsvp_log) < 5000 then
    insert into jesper40.rsvp_log (name, rsvp, arrival, comment)
    values (v_name, p_rsvp, v_arrival, v_comment);
  end if;

  return case when v_prev is null then 'created' else 'updated' end;
end;
$$;

-- Antal som tackat ja (visas på sidan när det är några stycken).
create function public.jesper40_public_stats()
returns json
language sql
stable
security definer
set search_path = ''
as $$
  select json_build_object('ja', count(*) filter (where g.rsvp = 'ja'))
  from jesper40.guests g
  where not g.removed;
$$;

-- ---------- Admin: OSA ----------

create function public.jesper40_admin_rsvps(p_password text)
returns table (id bigint, name text, rsvp text, arrival text, comment text, updated timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  return query
    select g.id, g.name, g.rsvp, g.arrival, g.comment, g.updated
    from jesper40.guests g
    where not g.removed and g.rsvp is not null
    order by g.updated desc;
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

-- ---------- Admin: Inbjudna ----------

create function public.jesper40_admin_invites(p_password text)
returns table (id bigint, name text, invited boolean, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  return query
    select i.id, i.name, i.invited, i.created_at
    from jesper40.invites i
    order by lower(i.name);
end;
$$;

create function public.jesper40_admin_add_invite(p_password text, p_name text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := jesper40.clean_name(p_name);
  v_id bigint;
begin
  perform jesper40.require_admin(p_password);
  if v_name is null or length(v_name) > 100 then
    raise exception 'Skriv ett namn (max 100 tecken).' using errcode = '22023';
  end if;
  -- Finns namnet redan returneras den raden (originalstavningen behålls).
  insert into jesper40.invites as i (name) values (v_name)
  on conflict ((lower(name))) do update set name = i.name
  returning i.id into v_id;
  return v_id;
end;
$$;

create function public.jesper40_admin_set_invite(p_password text, p_id bigint, p_invited boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  update jesper40.invites set invited = coalesce(p_invited, false) where id = p_id;
end;
$$;

create function public.jesper40_admin_remove_invite(p_password text, p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform jesper40.require_admin(p_password);
  delete from jesper40.invites where id = p_id;
end;
$$;

-- ---------- Rättigheter ----------
-- I Supabase får anon/authenticated EXECUTE via default privileges, så
-- "from public" räcker inte. Sidan kör som anon.

revoke all on function jesper40.require_admin(text), jesper40.clean_name(text)
  from public, anon, authenticated;

revoke all on function
  public.jesper40_submit_rsvp(text, text, text, text),
  public.jesper40_public_stats(),
  public.jesper40_admin_rsvps(text),
  public.jesper40_admin_remove_guest(text, bigint),
  public.jesper40_admin_invites(text),
  public.jesper40_admin_add_invite(text, text),
  public.jesper40_admin_set_invite(text, bigint, boolean),
  public.jesper40_admin_remove_invite(text, bigint)
from public, anon, authenticated;

grant execute on function
  public.jesper40_submit_rsvp(text, text, text, text),
  public.jesper40_public_stats(),
  public.jesper40_admin_rsvps(text),
  public.jesper40_admin_remove_guest(text, bigint),
  public.jesper40_admin_invites(text),
  public.jesper40_admin_add_invite(text, text),
  public.jesper40_admin_set_invite(text, bigint, boolean),
  public.jesper40_admin_remove_invite(text, bigint)
to anon;

-- ---------- Drift ----------
--
-- Sätt eller byt adminlösenordet (kör i SQL Editor, checka inte in lösenordet).
-- Använd ett långt lösenord; bf-kostnad 10 gör gissningar långsammare:
--   insert into jesper40.admin (password_hash)
--   values (extensions.crypt('DITT-LÖSENORD', extensions.gen_salt('bf', 10)))
--   on conflict (id) do update set password_hash = excluded.password_hash;
--
-- Ta fram en dold OSA igen:
--   update jesper40.guests set removed = false where name = 'Namn';
--
-- Se alla inskick för ett namn (t.ex. om någon skrivit över någon annan):
--   select * from jesper40.rsvp_log where lower(name) = lower('Namn') order by created_at;
