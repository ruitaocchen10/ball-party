-- Sabotage draft: an AV for each drafted card, so the final standings screen
-- can show "413 AV" next to a roster and also say what each of the players
-- inside that number is worth. `sabotage_draft_standings.roster_strength`
-- already sums this for the final roster (0056's roster_strengths), but the
-- per-pick number that sum is built from is never itself handed to a
-- client -- Approximate Value lives in `private.av_roster_players`, which
-- (see 0049) has no REST endpoint at all and is reachable only from inside
-- a security-definer function.
--
-- This reads every pick's AV, not just the ones that ended up in the final
-- roster (a round 14 X-Factor swap discards its round's own card, but that
-- card was still drafted and still worth showing). Visibility mirrors
-- 0073's own predicate on sabotage_draft_picks exactly -- a caller's own
-- picks always, another seat's once that seat's own turn has resolved --
-- restated here rather than relied on via RLS: this function is security
-- definer, and the picks table has no FORCE ROW LEVEL SECURITY (0052), so
-- the owner this function runs as would otherwise see every pick in the
-- match regardless of whose turn has resolved.
--
-- The pool join is by the picking seat's own spin (sabotage_draft_round_
-- spins), not a table-wide sabotage_draft_rounds.franchise_code -- 0059
-- dropped that column when franchise moved from one-per-round to one-per-
-- seat-per-round, the same join roster_strengths already uses.
create function sabotage_draft.pick_avs(p_match_id uuid)
returns table (user_id uuid, round_number smallint, av smallint)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  return query
    select p.user_id, p.round_number, pool.av
      from public.sabotage_draft_picks p
      join public.sabotage_draft_rounds r
        on r.match_id = p.match_id and r.round_number = p.round_number
      join public.sabotage_draft_round_spins spin
        on spin.match_id = p.match_id and spin.round_number = p.round_number and spin.user_id = p.user_id
      join private.av_roster_players pool
        on pool.franchise_code = spin.franchise_code
       and pool.player_id = p.player_id and pool.season = p.season
       and pool.slot_category = any(sabotage_draft_private.pool_categories(r.slot))
     where p.match_id = p_match_id
       and (
         p.user_id = auth.uid()
         or exists (
           select 1
             from public.sabotage_draft_matches m
             join public.sabotage_draft_players sp
               on sp.match_id = m.match_id and sp.user_id = p.user_id
            where m.match_id = p.match_id
              and (
                p.round_number < m.current_round
                or (p.round_number = m.current_round and sp.seat < m.active_seat)
              )
         )
       );
end;
$$;

revoke all on function sabotage_draft.pick_avs(uuid) from public, anon, authenticated;
grant execute on function sabotage_draft.pick_avs(uuid) to authenticated;
