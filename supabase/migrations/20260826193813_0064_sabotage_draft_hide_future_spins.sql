-- Sabotage draft: hide a round's spin until the table has actually reached
-- that round. Reverses a decision 0051 made on purpose and 0059 carried
-- forward: 0051's header argued "nothing about the team spin is secret ...
-- so there is no reason to hide round 9's spin from a table still on round
-- 1," and 0059 repeated that in its own header when it split the spin out
-- to one row per (round, player). Playtesting showed that reasoning wrong --
-- seeing every future round's franchise on turn one hands out real
-- information nobody is supposed to have yet (including a player's own
-- future spins, not just everyone else's), and undercuts the design doc's
-- own "you don't know your board yet" tension.
--
-- What stays true from 0051: a round's spin is still public to the whole
-- table the moment that round opens, not just to the seat whose turn it
-- currently is. A guess is aimed at whoever holds the turn, and everyone
-- else needs that seat's franchise -- and every other seat's franchise this
-- round -- visible before their own turn arrives, or there is no search
-- space to guess against (see docs/games/sabotage_draft.md's "one team spin
-- per player per slot" section). Only rounds strictly ahead of the match's
-- current_round are now hidden.
--
-- This is a policy change, not a shape change: the row still gets written
-- at deal time (see 0059's deal_board), same as the seed in
-- sabotage_draft_private.boards has been kept out of client reach since
-- 0051 for the identical reason -- letting a client precompute what's
-- coming defeats the point of not knowing yet. The franchise universe and
-- slot order were always public, so hiding the seed alone was never enough
-- on its own; this closes the gap 0051 left open on the spin itself.
drop policy sabotage_draft_round_spins_select_member on public.sabotage_draft_round_spins;

create policy sabotage_draft_round_spins_select_member on public.sabotage_draft_round_spins
  for select to authenticated using (
    private.is_match_member(match_id)
    and round_number <= (
      select m.current_round from public.sabotage_draft_matches m
       where m.match_id = sabotage_draft_round_spins.match_id
    )
  );

-- Realtime needs no separate change: it evaluates this same policy per
-- subscriber (see 0052's header on sabotage_draft_picks for the same
-- property), so a future round's INSERT already never reaches a client.
-- What it does NOT do is retroactively push a row that only just started
-- passing the policy -- current_round advancing is an UPDATE on
-- sabotage_draft_matches, not a change to this table -- so the client has
-- to notice that update and re-fetch, which SabotageDraftMatch already does
-- for every reason it refetches on a board change.
