-- Sabotage draft: within the current round, hide a seat's spin until that
-- seat's own turn actually arrives — not just from rounds strictly ahead.
--
-- 0064 deliberately made a round's spin visible to the whole table the
-- moment that round *opens*, seat order notwithstanding, reasoning that a
-- guess aimed at the active seat needs the rest of the table's franchises as
-- a search space (see its header, and docs/games/sabotage_draft.md's "OTHER
-- SPINS THIS ROUND" mockup). In practice that means a seat several turns out
-- has its franchise visible in the draft-order strip well before it's
-- remotely relevant to guess against, undercutting the same "you don't know
-- your board yet" tension 0064 itself invoked against showing future
-- rounds. This migration draws the line at seat order instead of round
-- number alone: a spin is visible once its round is strictly in the past,
-- OR once the round is current AND that seat's own turn has been reached
-- (seat <= the match's active_seat) — not merely because the round has
-- started for someone else.
--
-- No application-code change needed for this: FutureTurnCell and
-- RosterBoard already render "nothing yet" when a spin is absent from the
-- fetched set (see components/sabotage-draft/SabotageDraftMatch.tsx) — this
-- is purely a matter of which rows the query returns.
drop policy sabotage_draft_round_spins_select_member on public.sabotage_draft_round_spins;

create policy sabotage_draft_round_spins_select_member on public.sabotage_draft_round_spins
  for select to authenticated using (
    private.is_match_member(match_id)
    and exists (
      select 1
        from public.sabotage_draft_matches m
        join public.sabotage_draft_players sp
          on sp.match_id = m.match_id and sp.user_id = sabotage_draft_round_spins.user_id
       where m.match_id = sabotage_draft_round_spins.match_id
         and (
           sabotage_draft_round_spins.round_number < m.current_round
           or (
             sabotage_draft_round_spins.round_number = m.current_round
             and sp.seat <= m.active_seat
           )
         )
    )
  );

-- Realtime needs no separate change, same reasoning as 0064: it evaluates
-- this same policy per subscriber, and current_round/active_seat advancing
-- are UPDATEs on sabotage_draft_matches, not on this table, so the client's
-- existing refetch-on-board-change already picks up newly-visible rows.
