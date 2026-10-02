-- Wavelength's needle is transient UI state, not game state. It travels on a
-- private Broadcast channel so a client outside the match cannot inject or
-- observe a position. The active guesser alone may publish; every member may
-- receive. `realtime.messages` already has RLS enabled -- do not ALTER it.

create policy wavelength_needle_receive_member
on realtime.messages
for select to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and exists (
    select 1
      from public.wavelength_players p
     where p.user_id = (select auth.uid())
       and ('wavelength:' || p.match_id::text) = (select realtime.topic())
  )
);

create policy wavelength_needle_send_active_guesser
on realtime.messages
for insert to authenticated
with check (
  realtime.messages.extension = 'broadcast'
  and exists (
    select 1
      from public.wavelength_matches wm
      join public.wavelength_rounds r
        on r.match_id = wm.match_id and r.round = wm.current_round
     where wm.phase = 'guess'
       and r.guesser_id = (select auth.uid())
       and ('wavelength:' || wm.match_id::text) = (select realtime.topic())
  )
);
