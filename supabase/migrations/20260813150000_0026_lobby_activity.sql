-- A lobby seat is durable so a player can return after a closed tab. Activity
-- is a separate, renewable lease: it tells the room who is currently here,
-- permits recovery when a host disappears, and lets the janitor close rooms
-- that every player has abandoned.

alter table public.lobby_members
  add column last_seen_at timestamptz not null default now();

create index lobby_members_active_by_lobby
  on public.lobby_members (lobby_id, last_seen_at)
  where left_at is null;

-- A member renews this while their lobby screen is open. It deliberately does
-- not leave the room on an unload event: browsers do not reliably deliver one,
-- and preserving the seat is what makes reconnecting humane.
create function public.heartbeat_lobby(p_lobby_id uuid)
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
    select 1 from public.lobbies
     where id = p_lobby_id and closed_at is null
  ) then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  update public.lobby_members
     set last_seen_at = now()
   where lobby_id = p_lobby_id
     and user_id = v_user
     and left_at is null;

  if not found then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;
end;
$$;

-- A takeover is deliberately explicit rather than an automatic ownership
-- change. A refresh or a short network wobble must not silently replace a
-- host, but the room also must not be blocked once their activity lease is
-- genuinely stale. The caller's click is proof they are active, and the lock
-- makes two simultaneous claims deterministic.
create function public.claim_lobby_host(p_lobby_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_lobby public.lobbies;
  v_host_last_seen timestamptz;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_lobby
    from public.lobbies
   where id = p_lobby_id and closed_at is null
   for update;
  if not found then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id
       and user_id = v_user
       and left_at is null
  ) then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;

  if v_lobby.host_id = v_user then
    return;
  end if;

  select last_seen_at into v_host_last_seen
    from public.lobby_members
   where lobby_id = p_lobby_id
     and user_id = v_lobby.host_id
     and left_at is null;

  if v_host_last_seen is not null
     and v_host_last_seen >= now() - interval '30 seconds' then
    raise exception 'host_still_active' using errcode = 'P0001';
  end if;

  update public.lobby_members
     set last_seen_at = now()
   where lobby_id = p_lobby_id
     and user_id = v_user;

  update public.lobbies
     set host_id = v_user
   where id = p_lobby_id;
end;
$$;

-- The screen reads the same server-clock decision as claim_lobby_host, so a
-- client's clock skew cannot make the controls lie about the grace period.
create function public.lobby_host_is_active(p_lobby_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not private.is_lobby_member(p_lobby_id) then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;

  return exists (
    select 1
      from public.lobbies l
      join public.lobby_members m
        on m.lobby_id = l.id and m.user_id = l.host_id and m.left_at is null
     where l.id = p_lobby_id
       and l.closed_at is null
       and m.last_seen_at >= now() - interval '30 seconds'
  );
end;
$$;

-- Twenty minutes is long enough to survive a brief break, but finite so four
-- abandoned seats cannot hold a join code forever. close_lobby_internal also
-- abandons any run or match still attached to the room.
create function private.sweep_inactive_lobbies()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select l.id
     from public.lobbies l
     where l.closed_at is null
       and not exists (
         select 1 from public.runs r
          where r.lobby_id = l.id and r.status = 'active'
       )
       and not exists (
         select 1 from public.lobby_members m
          where m.lobby_id = l.id
            and m.left_at is null
            and m.last_seen_at >= now() - interval '20 minutes'
       )
  loop
    perform private.close_lobby_internal(r.id);
  end loop;
end;
$$;

create extension if not exists pg_cron;

select cron.schedule(
  'inactive-lobby-sweep',
  '* * * * *',
  $$ select private.sweep_inactive_lobbies() $$
);

revoke all on function private.sweep_inactive_lobbies() from public, anon, authenticated;
revoke all on function public.heartbeat_lobby(uuid) from public, anon;
revoke all on function public.claim_lobby_host(uuid) from public, anon;
revoke all on function public.lobby_host_is_active(uuid) from public, anon;

grant execute on function public.heartbeat_lobby(uuid) to authenticated;
grant execute on function public.claim_lobby_host(uuid) to authenticated;
grant execute on function public.lobby_host_is_active(uuid) to authenticated;
