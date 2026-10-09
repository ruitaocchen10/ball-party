-- Private profiles (Friends, BPP-3).
--
-- is_private limits who can open a player's profile body to their friends.
-- Username, display name and avatar stay searchable so friend requests are
-- still possible, and a private player still appears in rankings. The flag
-- is only enforced where profiles are read for other people (get_profile,
-- a later change); this migration adds the column and the one way to set it.
-- Direct UPDATEs are already closed by the column grants in 0183.

alter table public.profiles
  add column is_private boolean not null default false;

create function public.set_profile_private(p_private boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_profile public.profiles;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_private is null then
    raise exception 'invalid_value' using errcode = '22023';
  end if;
  select * into v_profile from public.profiles where id = v_me;
  if not found or v_profile.deleted_at is not null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_profile.is_guest then
    raise exception 'guests_cannot_set_privacy' using errcode = '42501';
  end if;

  update public.profiles set is_private = p_private where id = v_me;
  return p_private;
end;
$$;

revoke all on function public.set_profile_private(boolean) from public, anon;
grant execute on function public.set_profile_private(boolean) to authenticated;
