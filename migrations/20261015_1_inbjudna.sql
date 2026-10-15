-- 2026-10-15: Dela upp gästlistan i två helt separata listor.
--
--   jesper40.invites  "Inbjudna": Jespers egen avbockningslista
--   jesper40.guests   "OSA": bara riktiga svar från gästerna
--
-- Listorna matchas inte mot varandra. Gamla admin-funktioner ligger kvar
-- tills nya index.html är ute; de tas bort i 20261015_2_stada.sql.

-- 0) Säkerhetskopia av gästlistan som den såg ut före uppdelningen.
create table jesper40.guests_backup_20261015 as table jesper40.guests;
alter table jesper40.guests_backup_20261015 enable row level security;

-- 1) Inbjudna
create table jesper40.invites (
  id bigint generated always as identity primary key,
  name text not null check (length(name) between 1 and 100),
  invited boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index invites_name_key on jesper40.invites (lower(name));
alter table jesper40.invites enable row level security;

-- 2) Flytta de seedade namnen (rader utan OSA) till Inbjudna och ta bort
--    dem ur OSA-tabellen. Inga riktiga svar påverkas.
insert into jesper40.invites (name, invited, created_at)
select g.name, g.invited, g.created_at
from jesper40.guests g
where g.rsvp is null and not g.removed
order by g.id
on conflict do nothing;

delete from jesper40.guests where rsvp is null;

-- 3) Logg över alla inskick, så att ett överskrivet svar går att hitta igen.
create table jesper40.rsvp_log (
  id bigint generated always as identity primary key,
  name text not null,
  rsvp text not null,
  arrival text,
  comment text,
  created_at timestamptz not null default now()
);
alter table jesper40.rsvp_log enable row level security;

alter table jesper40.guests
  add constraint guests_arrival_check check (arrival in ('start', 'senare'));

-- 4) Namn städas likadant överallt: blanktecken (även hårda mellanslag)
--    slås ihop till ett mellanslag och trimmas.
create function jesper40.clean_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), '')
$$;

-- 5) Publik: gästens OSA. Returnerar 'created' eller 'updated' så att sidan
--    kan säga till om någon redan svarat under samma namn.
drop function public.jesper40_submit_rsvp(text, text, text);

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

-- Publik: antal som tackat ja (visas på sidan när det är några stycken).
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

-- 6) Admin: OSA-listan (bara rader med svar).
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

-- 7) Admin: Inbjudna.
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

-- 8) Explicita rättigheter. I Supabase får anon/authenticated EXECUTE via
--    default privileges, så "from public" räcker inte. Sidan kör som anon.
revoke all on function jesper40.require_admin(text), jesper40.clean_name(text)
  from public, anon, authenticated;

revoke all on function
  public.jesper40_submit_rsvp(text, text, text, text),
  public.jesper40_public_stats(),
  public.jesper40_admin_rsvps(text),
  public.jesper40_admin_invites(text),
  public.jesper40_admin_add_invite(text, text),
  public.jesper40_admin_set_invite(text, bigint, boolean),
  public.jesper40_admin_remove_invite(text, bigint),
  public.jesper40_admin_remove_guest(text, bigint),
  public.jesper40_admin_guests(text),
  public.jesper40_admin_add_guest(text, text, boolean),
  public.jesper40_admin_set_invited(text, bigint, boolean)
from public, anon, authenticated;

grant execute on function
  public.jesper40_submit_rsvp(text, text, text, text),
  public.jesper40_public_stats(),
  public.jesper40_admin_rsvps(text),
  public.jesper40_admin_invites(text),
  public.jesper40_admin_add_invite(text, text),
  public.jesper40_admin_set_invite(text, bigint, boolean),
  public.jesper40_admin_remove_invite(text, bigint),
  public.jesper40_admin_remove_guest(text, bigint),
  public.jesper40_admin_guests(text),
  public.jesper40_admin_add_guest(text, text, boolean),
  public.jesper40_admin_set_invited(text, bigint, boolean)
to anon;

notify pgrst, 'reload schema';
