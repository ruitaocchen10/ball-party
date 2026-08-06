-- The write API for lobbies.
--
-- These live in `public` because PostgREST only exposes functions from the
-- schemas in its config, and the client has to be able to call them. Unlike
-- the helpers in 0004, the security advisor warning on these is intentional:
-- they ARE the write surface. Every one derives identity from auth.uid() and
-- never from an argument, which is what keeps rule enforcement off the client.
--
-- The tables still have no INSERT/UPDATE/DELETE policies. This is the only way
-- a player can change a lobby.

-- Codes get read aloud across a room, so the alphabet drops the characters
-- people mishear or mistype: 0/O, 1/I/L. 31^5 is ~28.6M combinations, and
-- uniqueness is only enforced across OPEN lobbies, so exhaustion is not real.
create function private.generate_lobby_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
           substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ',
                  1 + floor(random() * 31)::int, 1),
           '')
  from generate_series(1, 5);
$$;

-- Closing is its own step because three things must happen together: the room
-- shuts, everyone still in it is marked out, and any run in flight is recorded
-- as abandoned rather than left dangling as 'active' forever.
create function private.close_lobby_internal(p_lobby_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.lobbies
     set closed_at = now()
   where id = p_lobby_id and closed_at is null;

  update public.lobby_members
     set left_at = now()
   where lobby_id = p_lobby_id and left_at is null;

  update public.runs
     set status = 'abandoned'::public.run_status, ended_at = now()
   where lobby_id = p_lobby_id and status = 'active'::public.run_status;
end;
$$;

-- Leaving has two consequences beyond the member row, and both have to happen
-- inside the same transaction or the room ends up hostless or immortal.
create function private.leave_lobby_internal(p_lobby_id uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lobby    public.lobbies;
  v_new_host uuid;
begin
  select * into v_lobby from public.lobbies where id = p_lobby_id for update;
  if not found then
    return;
  end if;

  update public.lobby_members
     set left_at = now()
   where lobby_id = p_lobby_id and user_id = p_user and left_at is null;

  -- Host migration: the room outlives its creator. Longest-tenured player
  -- takes over, with user_id as a deterministic tiebreak.
  if v_lobby.host_id = p_user then
    select user_id into v_new_host
      from public.lobby_members
     where lobby_id = p_lobby_id and left_at is null
     order by joined_at, user_id
     limit 1;

    if v_new_host is not null then
      update public.lobbies set host_id = v_new_host where id = p_lobby_id;
    end if;
  end if;

  -- Last one out closes the room, which frees the code for reuse.
  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and left_at is null
  ) then
    perform private.close_lobby_internal(p_lobby_id);
  end if;
end;
$$;

-- You are in exactly one room at a time. Without this you could be snapshotted
-- into two concurrent runs, and a stale membership in a room you forgot about
-- would keep your profile readable to those players indefinitely.
create function private.leave_all_lobbies(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select lobby_id from public.lobby_members
     where user_id = p_user and left_at is null
  loop
    perform private.leave_lobby_internal(r.lobby_id, p_user);
  end loop;
end;
$$;

-- ------------------------------------------------------------ the write API --

create function public.create_lobby()
returns public.lobbies
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user    uuid := auth.uid();
  v_lobby   public.lobbies;
  v_attempt int := 0;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform private.leave_all_lobbies(v_user);

  -- Generate-and-retry rather than check-then-insert: the unique index is the
  -- only thing that can actually adjudicate a collision under concurrency.
  loop
    v_attempt := v_attempt + 1;
    begin
      insert into public.lobbies (code, host_id)
      values (private.generate_lobby_code(), v_user)
      returning * into v_lobby;
      exit;
    exception when unique_violation then
      if v_attempt >= 10 then
        raise exception 'code_generation_failed' using errcode = 'P0001';
      end if;
    end;
  end loop;

  insert into public.lobby_members (lobby_id, user_id) values (v_lobby.id, v_user);

  return v_lobby;
end;
$$;

create function public.join_lobby(p_code text)
returns public.lobbies
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_code   text := upper(trim(coalesce(p_code, '')));
  v_lobby  public.lobbies;
  v_others int;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- The lock is taken here and held for the rest of the transaction, so the
  -- capacity check below cannot be raced by a second joiner.
  select * into v_lobby
    from public.lobbies
   where code = v_code and closed_at is null
   for update;

  if not found then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  -- Rejoining a room you are already in is a no-op, not an error. A flaky
  -- connection retrying the call must not be punished for it.
  if exists (
    select 1 from public.lobby_members
     where lobby_id = v_lobby.id and user_id = v_user and left_at is null
  ) then
    return v_lobby;
  end if;

  select count(*) into v_others
    from public.lobby_members
   where lobby_id = v_lobby.id and user_id <> v_user and left_at is null;

  if v_others >= 4 then
    raise exception 'lobby_full' using errcode = 'P0001';
  end if;

  -- Only past this point is the join guaranteed to succeed, so this is the
  -- earliest safe moment to give up the previous room. Leaving any sooner
  -- means a failed join strands the player with no lobby at all.
  perform private.leave_all_lobbies(v_user);

  -- A returning player keeps their original joined_at, so walking out and
  -- coming back does not promote them in the host succession order.
  insert into public.lobby_members (lobby_id, user_id)
  values (v_lobby.id, v_user)
  on conflict (lobby_id, user_id) do update set left_at = null;

  return v_lobby;
end;
$$;

create function public.leave_lobby(p_lobby_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and user_id = v_user and left_at is null
  ) then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;

  perform private.leave_lobby_internal(p_lobby_id, v_user);
end;
$$;

create function public.close_lobby(p_lobby_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_lobby public.lobbies;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_lobby
    from public.lobbies
   where id = p_lobby_id and closed_at is null
   for update;

  if not found then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  if v_lobby.host_id <> v_user then
    raise exception 'not_host' using errcode = '42501';
  end if;

  perform private.close_lobby_internal(p_lobby_id);
end;
$$;

-- CREATE FUNCTION grants EXECUTE to PUBLIC by default, which would hand these
-- to anon. Take it back and hand it only to signed-in users.
revoke all on function private.generate_lobby_code()             from public, anon, authenticated;
revoke all on function private.close_lobby_internal(uuid)        from public, anon, authenticated;
revoke all on function private.leave_lobby_internal(uuid, uuid)  from public, anon, authenticated;
revoke all on function private.leave_all_lobbies(uuid)           from public, anon, authenticated;

revoke all on function public.create_lobby()      from public, anon;
revoke all on function public.join_lobby(text)    from public, anon;
revoke all on function public.leave_lobby(uuid)   from public, anon;
revoke all on function public.close_lobby(uuid)   from public, anon;

grant execute on function public.create_lobby()    to authenticated;
grant execute on function public.join_lobby(text)  to authenticated;
grant execute on function public.leave_lobby(uuid) to authenticated;
grant execute on function public.close_lobby(uuid) to authenticated;
