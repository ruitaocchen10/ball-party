-- Security hardening for the SECURITY DEFINER helpers.
--
-- Anything in `public` is published by PostgREST, so every helper was also a
-- callable /rest/v1/rpc/ endpoint. These functions exist to bypass RLS; they
-- should not be reachable as API surface. `private` is not in PostgREST's
-- exposed schema list, so moving them removes the endpoint while leaving the
-- policies that call them working.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

-- Policies depend on the functions, so they must go first.
drop policy if exists lobbies_select_member          on public.lobbies;
drop policy if exists lobby_members_select_member    on public.lobby_members;
drop policy if exists runs_select_member             on public.runs;
drop policy if exists run_participants_select_member on public.run_participants;
drop policy if exists matches_select_member          on public.matches;
drop policy if exists match_players_select_member    on public.match_players;
drop policy if exists profiles_select_co_player      on public.profiles;

drop function if exists public.is_lobby_member(uuid);
drop function if exists public.is_run_member(uuid);
drop function if exists public.shares_lobby_with(uuid);

create function private.is_lobby_member(p_lobby_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1 from public.lobby_members
    where lobby_id = p_lobby_id and user_id = auth.uid() and left_at is null
  );
$$;

create function private.is_run_member(p_run_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1
    from public.runs r
    join public.lobby_members m on m.lobby_id = r.lobby_id
    where r.id = p_run_id and m.user_id = auth.uid() and m.left_at is null
  );
$$;

-- No left_at filter here, unlike the two above. A player who leaves mid-party
-- stays a run participant and keeps their points, so the players still in the
-- room must be able to render that name in the standings.
create function private.shares_lobby_with(p_user_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1
    from public.lobby_members mine
    join public.lobby_members theirs on theirs.lobby_id = mine.lobby_id
    where mine.user_id = auth.uid() and theirs.user_id = p_user_id
  );
$$;

-- Policy expressions are evaluated as the invoking role, so authenticated
-- still needs EXECUTE. anon deliberately gets nothing.
revoke all on function private.is_lobby_member(uuid)   from public, anon;
revoke all on function private.is_run_member(uuid)     from public, anon;
revoke all on function private.shares_lobby_with(uuid) from public, anon;
grant execute on function private.is_lobby_member(uuid)   to authenticated;
grant execute on function private.is_run_member(uuid)     to authenticated;
grant execute on function private.shares_lobby_with(uuid) to authenticated;

create policy lobbies_select_member on public.lobbies
  for select to authenticated using (private.is_lobby_member(id));

create policy lobby_members_select_member on public.lobby_members
  for select to authenticated using (private.is_lobby_member(lobby_id));

create policy runs_select_member on public.runs
  for select to authenticated using (private.is_lobby_member(lobby_id));

create policy run_participants_select_member on public.run_participants
  for select to authenticated using (private.is_run_member(run_id));

create policy matches_select_member on public.matches
  for select to authenticated using (private.is_run_member(run_id));

create policy match_players_select_member on public.match_players
  for select to authenticated using (private.is_run_member(run_id));

create policy profiles_select_co_player on public.profiles
  for select to authenticated
  using (
    private.shares_lobby_with(id)
    and (auth.jwt() ->> 'is_anonymous')::boolean is not true
  );

-- handle_new_user is only ever reached through the auth.users trigger, so it
-- has no business being an RPC endpoint either.
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();

create function private.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
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
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function private.handle_new_user();

-- Flagged by the linter: no search_path pinned. It touches only NEW, so the
-- empty path is safe.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
