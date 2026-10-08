-- Account deletion now also stops the account from signing in.
--
-- 0110 anonymized public.profiles and left auth.users alone, which meant the
-- old email/password or Google login still worked afterward and simply landed
-- on a "Deleted player". That is not deletion from the player's side, and App
-- Store review expects it to be.
--
-- This sets auth.users.banned_until on the caller's own row. GoTrue rejects a
-- banned user on every sign-in path (password, OAuth, Apple id token) and on
-- refresh-token use, so no new session can be minted. It is deliberately the
-- narrowest write that achieves that, rather than the hook or credential
-- scrubbing 0110 weighed: one column, on auth.uid()'s own row, with nothing
-- caller-controlled in the statement. An auth hook was rejected because it must
-- be switched on by hand in each hosted project, and a missed toggle would fail
-- silently. The date is a far-future timestamp rather than 'infinity' because
-- GoTrue parses this column into a Go time.
--
-- The email, password hash and OAuth identities stay in auth.users, so the
-- address cannot be re-registered. Removing them is a separate, larger step
-- that needs a service-role client.
--
-- Avatar files are not touched here. Deleting storage.objects rows from SQL
-- leaves the underlying file behind, so the clients remove them through the
-- Storage API (policy avatars_delete_own) before calling this function.
create or replace function public.delete_own_account()
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
         deleted_at = coalesce(deleted_at, now())
   where id = v_user;

  update auth.users
     set banned_until = now() + interval '100 years'
   where id = v_user;
end;
$$;
