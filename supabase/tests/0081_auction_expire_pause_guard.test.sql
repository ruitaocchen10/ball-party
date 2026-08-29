-- auction_private.expire's pause guard.
--
-- Every other game's expire already refuses to touch a match that isn't
-- 'playing'; auction's didn't, because its lot_preview/sold branches call
-- open_bidding/advance directly rather than going through apply()'s status
-- check. A stray expire_turn landing during a pause used to set a fresh,
-- real-time-based deadline that resume_match would then shift forward a
-- second time, on top of one that was never stale to begin with.
begin;
select plan(3);

\ir support/harness.psql

select tests.act_as_admin();

insert into tests.fx (k, v) values ('m', tests.deal(2, 0.41));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm');
select auction_private.advance((select v from tests.fx where k = 'm'));
update public.auction_matches set phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');

-- Paused, with a deadline that has already passed.
update public.matches set status = 'paused', paused_at = now()
 where id = (select v from tests.fx where k = 'm');
select auction_private.expire((select v from tests.fx where k = 'm'));

select is(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')),
  'lot_preview',
  'a paused match is left in lot_preview rather than advanced to bidding'
);

select ok(
  (select phase_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm')) <= now(),
  'and its passed deadline is left alone rather than replaced with a fresh one'
);

-- The same setup, unpaused, still advances normally -- the guard isn't
-- blocking anything it shouldn't.
update public.matches set status = 'playing', paused_at = null
 where id = (select v from tests.fx where k = 'm');
select auction_private.expire((select v from tests.fx where k = 'm'));

select is(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')),
  'bidding',
  'and once resumed, expire advances it exactly as it always did'
);

select * from finish();
rollback;
