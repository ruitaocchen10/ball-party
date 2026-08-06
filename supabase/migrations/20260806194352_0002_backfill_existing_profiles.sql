-- One account was created through the auth flow before 0001 was ever applied,
-- so it has an auth.users row and no profile. Same name-resolution logic as
-- handle_new_user, so a backfilled row is indistinguishable from a trigger one.

insert into public.profiles (id, display_name, avatar_url)
select
  u.id,
  left(
    coalesce(
      nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
      nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
      'Player'
    ),
    16
  ),
  u.raw_user_meta_data ->> 'avatar_url'
from auth.users u
on conflict (id) do nothing;
