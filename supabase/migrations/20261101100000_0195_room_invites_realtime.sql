-- Room invites arrive live (follow-up to 0189).
--
-- 0189 made invites pull-only: the recipient saw one only after reloading the
-- Party page (web) or reopening / pulling the Party tab (iOS). This lets the
-- recipient's open client hear about a new invite over Realtime and re-read
-- list_room_invites.
--
-- Realtime's postgres_changes only delivers rows the subscriber could SELECT,
-- and 0189 intended the table to have no client access at all. So this gives
-- the recipient a read of their own rows, nothing else: no write grants, and
-- the RPCs stay the only way to create, accept or decline. The grant is stated
-- explicitly rather than relied on from platform defaults. The SELECT policy is the same bare
-- `col = auth.uid()` shape as auction_scouting_hints (0159), which is what
-- keeps one player's invites off another player's socket.
--
-- The event is only a nudge. Clients ignore its payload and re-read
-- list_room_invites, which still applies the 24-hour life, the open-room check
-- and the friendship check, so Realtime cannot show an invite the RPC would not.

grant select on table public.room_invites to authenticated;

create policy room_invites_select_recipient on public.room_invites
  for select to authenticated using (recipient_id = auth.uid());

alter publication supabase_realtime add table public.room_invites;
