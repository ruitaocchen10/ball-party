-- 2v2 Wavelength: let a round's psychic read the card and target dealt only
-- to them (issue #98).
--
-- These two tables deliberately hold whole hidden rows rather than columns on
-- wavelength_rounds: RLS can make a row absent from a client response, whereas
-- it cannot hide only one column. The policy therefore has to prove ownership
-- from the round assignment, not merely membership in the match. Keep both
-- tables out of supabase_realtime: they are read on demand by their owner and
-- must never be fanned out over a match channel.

create policy wavelength_cards_select_psychic on public.wavelength_cards
  for select to authenticated
  using (
    exists (
      select 1
        from public.wavelength_rounds r
       where r.match_id = wavelength_cards.match_id
         and r.round = wavelength_cards.round
         and r.psychic_id = auth.uid()
    )
  );

create policy wavelength_targets_select_psychic on public.wavelength_targets
  for select to authenticated
  using (
    exists (
      select 1
        from public.wavelength_rounds r
       where r.match_id = wavelength_targets.match_id
         and r.round = wavelength_targets.round
         and r.psychic_id = auth.uid()
    )
  );

-- No write policy: wavelength_private.deal_board remains the only writer.
grant select on public.wavelength_cards to authenticated;
grant select on public.wavelength_targets to authenticated;
