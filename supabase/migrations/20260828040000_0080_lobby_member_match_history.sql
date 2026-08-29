-- The lobby's player-form card wants each seated member's career match
-- history, not just theirs (`match_players_select_member`/
-- `matches_select_member` already cover that — see 0004 — because they gate
-- on the viewer's own current lobby membership, not whose row it is).
--
-- Widening those two policies to cover co-players, the way
-- `profiles_select_co_player` does for `profiles` via `shares_lobby_with`,
-- was considered and rejected: `shares_lobby_with` has no `left_at` filter
-- ("ever shared a lobby, forever"), and broadening two heavily-used core
-- tables' SELECT policies for one card has a much bigger blast radius than
-- the feature needs. A dedicated RPC, scoped to *current* membership in one
-- specific lobby, is the same shape `heartbeat_lobby` (0026) already uses.

create type public.match_history_row as (
  user_id   uuid,
  match_id  uuid,
  game      text,
  ended_at  timestamptz,
  placement smallint,
  raw_score numeric
);

create function private.lobby_member_match_history(p_lobby_id uuid)
returns setof public.match_history_row
language sql
stable
security definer
set search_path = ''
as $$
  select mp.user_id, mp.match_id, m.game, m.ended_at, mp.placement, mp.raw_score
    from public.match_players mp
    join public.matches m on m.id = mp.match_id
   where m.status = 'complete'::public.match_status
     and m.ended_at is not null
     and mp.user_id in (
       select user_id from public.lobby_members
        where lobby_id = p_lobby_id and left_at is null
     );
$$;

-- Membership check happens in the public wrapper, same split `heartbeat_lobby`
-- uses: the private function does the (already-authorized) read, the public
-- one is the only thing PostgREST can call and is where the caller's own
-- standing gets checked.
create function public.lobby_member_match_history(p_lobby_id uuid)
returns setof public.match_history_row
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_lobby_member(p_lobby_id) then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;

  return query select * from private.lobby_member_match_history(p_lobby_id);
end;
$$;

revoke all on function private.lobby_member_match_history(uuid) from public, anon, authenticated;
revoke all on function public.lobby_member_match_history(uuid) from public, anon;
grant execute on function public.lobby_member_match_history(uuid) to authenticated;
