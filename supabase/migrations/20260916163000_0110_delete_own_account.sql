-- Self-serve account deletion anonymizes rather than deletes: other players'
-- match history and take/comment threads reference this profile by id, and
-- cascading the row away would take their record with it.
--
-- This only scrubs public.profiles, deliberately. auth.users/auth.identities
-- are left untouched — this project has no service-role client, and nulling
-- those columns from a function grantable to any `authenticated` caller is a
-- materially bigger step than the one precedent for a security-definer
-- function writing to auth.users (private.cleanup_guest_accounts, which only
-- ever touches credential-less anonymous rows and is never granted to
-- `authenticated`). It also wouldn't revoke an already-issued access token
-- anyway. The server action pairs this with a global sign-out instead, which
-- is the one mitigation available without adding that infrastructure.
alter table public.profiles
  add column deleted_at timestamptz;

create function public.delete_own_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  update public.profiles
     set display_name = 'Deleted player',
         avatar_url = null,
         rankings_visible = false,
         deleted_at = now()
   where id = v_user
     and deleted_at is null;
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
