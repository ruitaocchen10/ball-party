-- The sweep's candidate scan is intentionally cheap, but it must not be the
-- final decision: a player can heartbeat between that scan and closure. Lock
-- the room and re-evaluate both conditions before closing it.
create function private.close_lobby_if_inactive(p_lobby_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lobby public.lobbies;
begin
  select * into v_lobby
    from public.lobbies
   where id = p_lobby_id and closed_at is null
   for update;
  if not found then
    return;
  end if;

  if exists (
    select 1 from public.runs active_run
     where active_run.lobby_id = p_lobby_id
       and active_run.status = 'active'
  ) or exists (
    select 1 from public.lobby_members m
     where m.lobby_id = p_lobby_id
       and m.left_at is null
       and m.last_seen_at >= now() - interval '20 minutes'
  ) then
    return;
  end if;

  perform private.close_lobby_internal(p_lobby_id);
end;
$$;

create or replace function private.sweep_inactive_lobbies()
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
         select 1 from public.runs active_run
          where active_run.lobby_id = l.id
            and active_run.status = 'active'
       )
       and not exists (
         select 1 from public.lobby_members m
          where m.lobby_id = l.id
            and m.left_at is null
            and m.last_seen_at >= now() - interval '20 minutes'
       )
  loop
    perform private.close_lobby_if_inactive(r.id);
  end loop;
end;
$$;

revoke all on function private.close_lobby_if_inactive(uuid) from public, anon, authenticated;
