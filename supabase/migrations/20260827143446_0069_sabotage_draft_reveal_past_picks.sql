-- Sabotage draft: reveal a pick's identity to the whole table once its own
-- round has fully closed. Reverses part of what 0052 set out as permanent
-- -- its own header called a pick "a different shape of secret ... hidden
-- from every player except the one who made it, indefinitely, until a
-- later ticket resolves it." This is that ticket.
--
-- The reasoning holds only because of what 0062/0063 already guarantee: a
-- guess is scoped to (round, target) -- each other seat gets exactly one
-- shot at a given seat's pick, spent sometime during that seat's own turn
-- within that same round (see docs/games/sabotage_draft.md's "one shared
-- clock per turn" section). Once the match's current_round moves past a
-- round, nobody can ever guess against that round's picks again -- there is
-- no guessing window left to protect. Keeping a pick concealed past that
-- point serves no mechanic; it only made the roster board and the turn
-- strip's own settled cells show less than they could safely show.
--
-- The current round is unaffected: while round_number = current_round, a
-- pick stays exactly as hidden as 0052 made it, for the same reason 0064
-- keeps a future round's spin hidden -- the design doc's "you don't know
-- yet" tension depends on it, and here that specifically includes not
-- knowing a seat whose turn hasn't come up yet this round.
drop policy sabotage_draft_picks_select_own on public.sabotage_draft_picks;

create policy sabotage_draft_picks_select_own_or_past on public.sabotage_draft_picks
  for select to authenticated using (
    user_id = auth.uid()
    or (
      private.is_match_member(match_id)
      and round_number < (
        select m.current_round from public.sabotage_draft_matches m
         where m.match_id = sabotage_draft_picks.match_id
      )
    )
  );

-- Realtime needs no separate change, and the same caveat 0064 already
-- documents applies here too: current_round advancing is an UPDATE on
-- sabotage_draft_matches, not a change to this table, so a client learns
-- about newly-visible past picks by refetching on that board update --
-- which SabotageDraftMatch already does for every other reason it refetches
-- on a board change.
