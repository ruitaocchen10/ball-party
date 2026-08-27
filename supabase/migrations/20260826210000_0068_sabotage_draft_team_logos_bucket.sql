-- A public Storage bucket for sabotage draft's franchise logos.
--
-- Unlike 0065's player headshots (an external CDN URL per player, hotlinked
-- straight from its source), these are fetched once by
-- scripts/team_logos/build_logos.mjs and uploaded here under
-- `{franchise_code}.png` -- see that script's README for why: there is no
-- equivalent of the headshot CDN for team logos that this app can hotlink
-- long-term without risk, so the pipeline owns a stable copy instead.
--
-- Public, not `private` the way the roster pool and its headshots are: a
-- logo carries no information a client shouldn't have ahead of time --
-- unlike a headshot (which would leak a pick's identity) or the pool itself
-- (which would leak what a round might deal), the 32-franchise universe is
-- already public knowledge the client has held since franchises.ts, and a
-- round's own franchise is public from the moment that round opens (see
-- 0064's header). A public bucket serves reads with no RLS policy needed --
-- the simplest shape for a static asset nothing gates.
insert into storage.buckets (id, name, public)
values ('team-logos', 'team-logos', true)
on conflict (id) do nothing;
