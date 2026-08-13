-- The hosted project grants SELECT on public relations by default. State this
-- explicitly for this late-added replicated table so local development and
-- production have the same player-visible surface.
grant select on public.post_game_actions to authenticated;
