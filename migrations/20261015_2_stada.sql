-- 2026-10-15: Städning efter att nya index.html är ute.
-- De gamla admin-funktionerna användes bara av den gamla sidan, och
-- guests.invited ersätts av den separata listan jesper40.invites.

drop function public.jesper40_admin_guests(text);
drop function public.jesper40_admin_add_guest(text, text, boolean);
drop function public.jesper40_admin_set_invited(text, bigint, boolean);

alter table jesper40.guests drop column invited;

notify pgrst, 'reload schema';
