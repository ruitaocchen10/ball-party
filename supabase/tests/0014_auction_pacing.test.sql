-- Pacing, and the janitor's split grace.
--
-- The grace split is the part worth testing: a live turn keeps its full minute
-- because there is a real person behind it whose network might have hiccupped,
-- while a preview or a sold acknowledgement is rescued almost immediately
-- because there is no decision in either of them to protect. Getting that
-- backwards is what made a lot with no player actions take 127 seconds.
begin;
select plan(9);
\ir support/harness.psql

select tests.act_as_admin();

-- ------------------------------------------------------------- the clocks --

insert into tests.fx (k, v) values ('m', tests.deal(2, 0.41));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm');
select auction_private.advance((select v from tests.fx where k = 'm'));

select ok(
  (select phase_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm'))
    between now() + interval '4 seconds' and now() + interval '6 seconds',
  'a preview runs for five seconds'
);

update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'm');
select auction_private.expire((select v from tests.fx where k = 'm'));

select ok(
  (select turn_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm'))
    between now() + interval '19 seconds' and now() + interval '21 seconds',
  'a live turn runs for twenty seconds'
);

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm')));
select auction.pass_lot((select v from tests.fx where k = 'm'));
select tests.act_as_admin();

select ok(
  (select phase_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm'))
    between now() + interval '4 seconds' and now() + interval '6 seconds',
  'and a sold acknowledgement is held for five seconds'
);

-- ------------------------------------------------- the janitor is a backstop --

-- A timer phase nobody advanced. There is no player decision inside a preview,
-- so nothing is gained by waiting on it.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('ms', tests.deal(2, 0.52));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'ms');
select auction_private.advance((select v from tests.fx where k = 'ms'));
update public.auction_matches set phase_deadline = now() - interval '5 seconds' where match_id = (select v from tests.fx where k = 'ms');

select auction_private.sweep();
select isnt(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'ms')),
  'lot_preview',
  'a stalled preview is rescued by the sweep within seconds rather than a minute'
);

-- The same sweep must not cut a real decision short.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('mb', tests.deal_and_open(3, 0.63));
insert into tests.fx (k, v) select 'clock', tests.on_clock((select v from tests.fx where k = 'mb'));
update public.auction_matches set turn_deadline = now() - interval '10 seconds' where match_id = (select v from tests.fx where k = 'mb');

select auction_private.sweep();
select is(
  tests.on_clock((select v from tests.fx where k = 'mb')),
  (select v from tests.fx where k = 'clock'),
  'a live turn ten seconds past its deadline keeps its grace, because a person is behind it'
);
select is(
  (select count(*)::int from public.auction_bids where match_id = (select v from tests.fx where k = 'mb') and by_timeout),
  0,
  'and nobody has been auto-passed'
);

-- Past the full minute, the same turn is swept.
update public.auction_matches set turn_deadline = now() - interval '2 minutes' where match_id = (select v from tests.fx where k = 'mb');
select auction_private.sweep();
select is(
  (select count(*)::int from public.auction_bids where match_id = (select v from tests.fx where k = 'mb') and by_timeout),
  1,
  'an abandoned turn is auto-passed once its grace really has run out'
);

-- One pass drains what it can rather than advancing a single phase and waiting
-- another thirty seconds for the next one.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('md', tests.deal(2, 0.74));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'md');
select auction_private.advance((select v from tests.fx where k = 'md'));
update public.auction_matches set phase_deadline = now() - interval '5 seconds' where match_id = (select v from tests.fx where k = 'md');
select auction_private.sweep();
select ok(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'md')) in ('bidding', 'sold', 'lot_preview'),
  'the drain leaves the board in a live phase rather than the one it was stuck in'
);
select isnt(
  (select coalesce(turn_deadline, phase_deadline) from public.auction_matches where match_id = (select v from tests.fx where k = 'md')),
  null,
  'with a deadline in front of it again'
);

select * from finish();
rollback;
