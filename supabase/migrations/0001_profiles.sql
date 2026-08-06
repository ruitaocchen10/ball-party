-- Account records for Ball Party.
--
-- auth.users is owned by Supabase and is not safe to read from application
-- queries. public.profiles is the app-facing mirror: one row per account,
-- holding the things the game needs (display name, avatar) and nothing else.

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 16),
  avatar_url   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Ball Party has no guest play, so an anonymous JWT gets nothing. Anonymous
-- sign-ins should also be disabled in the dashboard; this is the second lock.
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (
    auth.uid() = id
    and (auth.jwt() ->> 'is_anonymous')::boolean is not true
  );

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- No insert policy on purpose. Rows come from the trigger below, so a profile
-- can never exist without a matching auth.users row behind it.

-- Once sessions land, co-players need each other's display names. That is a
-- second SELECT policy scoped to shared sessions — not a widening of this one.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    -- Email signup sends display_name through options.data. Google sends
    -- full_name/name. Local-part of the email is the last resort so the
    -- not-null constraint can never fail a signup.
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
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row
  execute function public.touch_updated_at();
