-- Google can expose its profile image as either `avatar_url` or `picture` in
-- auth metadata. Keep the public profile projection agnostic to that provider
-- detail, while preserving any avatar a player has already chosen themselves.
create or replace function private.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url, is_guest)
  values (
    new.id,
    left(
      coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
        nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
        nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Player'
      ),
      16
    ),
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'avatar_url'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'picture'), '')
    ),
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Existing OAuth profiles should gain the provider image only when they have
-- no profile image of their own.
update public.profiles profile
   set avatar_url = coalesce(
     nullif(trim(auth_user.raw_user_meta_data ->> 'avatar_url'), ''),
     nullif(trim(auth_user.raw_user_meta_data ->> 'picture'), '')
   )
  from auth.users auth_user
 where auth_user.id = profile.id
   and profile.avatar_url is null
   and coalesce(
     nullif(trim(auth_user.raw_user_meta_data ->> 'avatar_url'), ''),
     nullif(trim(auth_user.raw_user_meta_data ->> 'picture'), '')
   ) is not null;
