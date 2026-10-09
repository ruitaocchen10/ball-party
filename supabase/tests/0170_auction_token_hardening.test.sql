-- Token hardening (0170): season-total Scout, the stuck-seat timeout, and the
-- sweep's coverage of the sealed phase.

begin;
select plan(11);

\ir support/harness.psql

-- ------------------------------------------------------------ season tiering --

select tests.act_as_admin();
select is(auction_private.season_tier('QB', 1000), 'great', 'a season total above the whole pool is great');
select is(auction_private.season_tier('QB', 0),    'rough', 'a season total below the whole pool is rough');
select is(
  auction_private.season_tier('QB', (select percentile_cont(0.5) within group (order by points) from private.player_seasons where position = 'QB')::numeric),
  'solid', 'the median QB season is solid'
);
select is(
  auction_private.season_tier('TE', (select percentile_cont(0.5) within group (order by points) from private.player_seasons where position = 'TE')::numeric),
  'solid', 'tiers are position-relative: the median TE season is solid too'
);

-- ----------------- a seat that cannot decline is awarded at once, not after 20s --

-- token_count 0: nothing to decide, so no stuck turn is created at all.
insert into tests.fx (k, v) values ('m1', tests.deal_and_open(2, 0.71, 'standard', 0::smallint));
insert into tests.fx (k, v) select 'm1_stuck', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm1') and ap.seat <> am.turn_seat;
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm1')));
select auction.pass_lot((select v from tests.fx where k = 'm1'));
select tests.act_as_admin();

select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  (select v from tests.fx where k = 'm1_stuck'),
  'the last live bidder with no token gets the lot immediately'
);
select is(
  (select stuck_seat from public.auction_matches where match_id = (select v from tests.fx where k = 'm1')),
  null,
  'and is never handed a stuck turn they could only wait out'
);

-- A seat whose token is already spent is the same story mid-match.
insert into tests.fx (k, v) values ('m6', tests.deal_and_open(2, 0.76));
insert into tests.fx (k, v) select 'm6_last', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm6') and ap.seat <> am.turn_seat;
update public.auction_players set used_pass_token = true
 where match_id = (select v from tests.fx where k = 'm6') and user_id = (select v from tests.fx where k = 'm6_last');
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm6')));
select auction.pass_lot((select v from tests.fx where k = 'm6'));
select tests.act_as_admin();
select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm6') and seq = 1),
  (select v from tests.fx where k = 'm6_last'),
  'a spent pass token means no stuck turn either'
);

-- with a token available, an idle timeout still must not burn it
insert into tests.fx (k, v) values ('m2', tests.deal_and_open(2, 0.72));
insert into tests.fx (k, v) select 'm2_stuck', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm2') and ap.seat <> am.turn_seat;
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm2')));
select auction.pass_lot((select v from tests.fx where k = 'm2'));
select tests.act_as_admin();
update public.auction_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm2');
select auction_private.expire((select v from tests.fx where k = 'm2'));
select is(
  (select used_pass_token from public.auction_players where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_stuck')),
  false,
  'an idle timeout never spends the stuck seat''s pass token'
);

-- ------------------------------------------------------------ the sweep --

-- A sealed lot whose clock ran out more than a minute ago is resolved by sweep.
insert into tests.fx (k, v) values ('m3', tests.deal_and_open(2, 0.73));
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm3')));
select auction.use_seal_token((select v from tests.fx where k = 'm3'));
select tests.act_as_admin();
update public.auction_matches set turn_deadline = now() - interval '2 minutes'
 where match_id = (select v from tests.fx where k = 'm3');
select auction_private.sweep();
select isnt(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm3')),
  'sealed',
  'sweep resolves an abandoned sealed lot'
);
select isnt(
  (select resolved_at from public.auction_lots where match_id = (select v from tests.fx where k = 'm3') and seq = 1),
  null,
  'and the lot is resolved'
);

-- One match that throws must not stop the sweep from reaching the next.
insert into tests.fx (k, v) values ('m4', tests.deal_and_open(2, 0.74));
update public.auction_matches set phase = 'bidding', turn_seat = null, turn_deadline = now() - interval '2 minutes'
 where match_id = (select v from tests.fx where k = 'm4');
insert into tests.fx (k, v) values ('m5', tests.deal_and_open(2, 0.75));
update public.auction_matches set turn_deadline = now() - interval '2 minutes'
 where match_id = (select v from tests.fx where k = 'm5');
select lives_ok($$ select auction_private.sweep() $$, 'sweep survives a match that raises');

select * from finish();
rollback;
