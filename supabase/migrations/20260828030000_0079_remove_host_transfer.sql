-- A lobby now has one fixed host. If that person leaves, the room closes and
-- the remaining players can start a new room; controls are never transferred.

drop function if exists public.claim_lobby_host(uuid);
drop function if exists public.lobby_host_is_active(uuid);

create or replace function private.leave_lobby_internal(p_lobby_id uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lobby public.lobbies;
begin
  select * into v_lobby from public.lobbies where id = p_lobby_id for update;
  if not found then
    return;
  end if;

  update public.lobby_members
     set left_at = now()
   where lobby_id = p_lobby_id and user_id = p_user and left_at is null;

  if v_lobby.host_id = p_user then
    perform private.close_lobby_internal(p_lobby_id);
    return;
  end if;

  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and left_at is null
  ) then
    perform private.close_lobby_internal(p_lobby_id);
  end if;
end;
$$;
