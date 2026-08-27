-- Sabotage draft: reveal a pick once its own turn has actually resolved,
-- not only once its whole round has closed.
--
-- 0069 drew the concealment boundary at the round: a pick stayed hidden
-- until `round_number < current_round`, reasoning that the guessing window
-- (each other seat's one shot per turn) stays open for the entire round.
-- That was more concealment than the mechanic actually needs -- the
-- guessing window for a given seat's pick closes the moment *that seat's
-- own turn* resolves (`resolve_turn` calls `advance_turn`, moving
-- `active_seat` past it), not when the rest of the round's later turns
-- finally play out too. A four-seat round kept seat 1's pick hidden through
-- seats 2, 3, and 4's entire turns even though nobody can ever guess
-- against seat 1's pick again once seat 1's own turn ended. This mirrors
-- 0071's identical move for spins -- draw the line at seat order within the
-- current round, not just at the round boundary -- applied here to the
-- pick's actual identity instead of just its spun franchise.
--
-- The live guessing window itself is unaffected: while a seat's own turn is
-- still open (seat = active_seat, that seat still the one on the clock),
-- its pick stays exactly as hidden as 0052 made it. Revealing it before the
-- turn resolves would let a "guess" be read straight off the answer instead
-- of aimed at a hidden card, undoing the entire mechanic
-- docs/games/sabotage_draft.md calls "the mechanic worth protecting."
drop policy sabotage_draft_picks_select_own_or_past on public.sabotage_draft_picks;

create policy sabotage_draft_picks_select_own_or_resolved on public.sabotage_draft_picks
  for select to authenticated using (
    user_id = auth.uid()
    or (
      private.is_match_member(match_id)
      and exists (
        select 1
          from public.sabotage_draft_matches m
          join public.sabotage_draft_players sp
            on sp.match_id = m.match_id and sp.user_id = sabotage_draft_picks.user_id
         where m.match_id = sabotage_draft_picks.match_id
           and (
             sabotage_draft_picks.round_number < m.current_round
             or (
               sabotage_draft_picks.round_number = m.current_round
               and sp.seat < m.active_seat
             )
           )
      )
    )
  );

-- Realtime needs no separate change, same reasoning as 0069/0071: a client
-- learns about newly-visible picks by refetching on the board update that
-- advance_turn always produces (active_seat or current_round changing),
-- which SabotageDraftMatch already does for every other reason it refetches
-- on a board change.
