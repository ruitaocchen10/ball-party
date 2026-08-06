-- Stop stamping left_at when the host closes a room.
--
-- Realtime evaluates RLS per subscriber at the moment it processes the change,
-- against current state — not against the state when the change was made. The
-- old version set closed_at and marked every member as left in one
-- transaction, so by the time Realtime tested is_lobby_member() for each
-- subscriber, every one of them had already left. The policy failed for
-- everybody and the "room closed" event reached nobody, leaving every client
-- parked on a room that no longer exists.
--
-- Members now stay attached to a closed lobby. is_lobby_member() keeps
-- returning true, the lobbies UPDATE carrying closed_at is delivered, and the
-- client reads closure from closed_at — which is the honest source of truth
-- anyway. They are detached later, by leave_all_lobbies, the next time they
-- create or join anything.
--
-- This only affects the host-initiated close. In the last-one-out path the
-- final member already has left_at set by leave_lobby_internal before this
-- runs, and there is nobody left to notify.

create or replace function private.close_lobby_internal(p_lobby_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.lobbies
     set closed_at = now()
   where id = p_lobby_id and closed_at is null;

  update public.runs
     set status = 'abandoned'::public.run_status, ended_at = now()
   where lobby_id = p_lobby_id and status = 'active'::public.run_status;
end;
$$;
