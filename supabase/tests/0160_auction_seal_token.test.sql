-- Seal token (0160): a live player may seal an untouched lot into
-- simultaneous blind bidding. Two properties matter most here, the same way
-- they mattered for 0159's scouting hints: the resolution math (highest
-- first-price bid wins, ties go to whoever's closest to the opener) has to
-- be exactly right, and a losing bid's amount must never reach the other
-- player's own session -- not hidden by the UI, genuinely never sent.

begin;
select plan(18);

\ir support/harness.psql

-- ------------------------------------------------------------- sealing it --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m1', tests.deal_and_open(2, 0.41));
insert into tests.fx (k, v) select 'm1_opener', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm1') and ap.seat = am.turn_seat;
insert into tests.fx (k, v) select 'm1_other', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm1') and ap.seat <> am.turn_seat;

select tests.act_as((select v from tests.fx where k = 'm1_opener'));
select auction.use_seal_token((select v from tests.fx where k = 'm1'));

select tests.act_as_admin();
select is(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm1')),
  'sealed',
  'use_seal_token moves the lot into sealed bidding'
);
select is(
  (select turn_seat from public.auction_matches where match_id = (select v from tests.fx where k = 'm1')),
  null,
  'nobody is singled out as "on the clock" once sealed -- both players act at once'
);
select ok(
  (select turn_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm1'))
    between now() + interval '19 seconds' and now() + interval '21 seconds',
  'a 20-second shared clock opens'
);
select is(
  (select used_seal_token from public.auction_players
    where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_opener')),
  true,
  'spends the sealing player''s own token'
);

select tests.act_as((select v from tests.fx where k = 'm1_opener'));
select throws_ok(
  format($$ select auction.use_seal_token(%L) $$, (select v from tests.fx where k = 'm1')),
  'P0001', 'sealing_not_available',
  'a lot already sealed cannot be sealed again'
);

-- ------------------------------------------------------- resolution, and its leak --

select tests.act_as((select v from tests.fx where k = 'm1_opener'));
select auction.submit_sealed_bid((select v from tests.fx where k = 'm1'), 7);

select tests.act_as((select v from tests.fx where k = 'm1_other'));
select is(
  (select count(*)::int from public.auction_sealed_bids
    where match_id = (select v from tests.fx where k = 'm1') and seq = 1
      and user_id = (select v from tests.fx where k = 'm1_opener')),
  0,
  'the opponent''s own session cannot read the first bid while it''s still pending -- not hidden, absent'
);
select is(
  (select submitted from public.auction_sealed_bid_statuses
    where match_id = (select v from tests.fx where k = 'm1') and seq = 1
      and user_id = (select v from tests.fx where k = 'm1_opener')),
  true,
  'but its presence (not its value) is visible, so "waiting on" is renderable'
);

select auction.submit_sealed_bid((select v from tests.fx where k = 'm1'), 3);

select tests.act_as_admin();
select is(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm1')),
  'sold',
  'the second submission resolves the lot immediately -- it does not wait for the clock'
);
select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  (select v from tests.fx where k = 'm1_opener'),
  'the higher bid wins'
);
select is(
  (select price from public.auction_lots where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  7,
  'at the price it actually bid -- first price, not the runner-up''s'
);
select is(
  (select budget from public.auction_players
    where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_other')),
  (select purse from public.auction_matches where match_id = (select v from tests.fx where k = 'm1')),
  'and the loser is charged nothing at all'
);

-- ------------------------------------------------------------------ the tie --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m2', tests.deal_and_open(2, 0.42));
insert into tests.num (k, v) select 'm2_opener_seat', opener_seat
  from public.auction_matches where match_id = (select v from tests.fx where k = 'm2');
insert into tests.fx (k, v) select 'm2_opener', ap.user_id
  from public.auction_players ap where ap.match_id = (select v from tests.fx where k = 'm2') and ap.seat = (select v::smallint from tests.num where k = 'm2_opener_seat');
insert into tests.fx (k, v) select 'm2_other', ap.user_id
  from public.auction_players ap where ap.match_id = (select v from tests.fx where k = 'm2') and ap.seat <> (select v::smallint from tests.num where k = 'm2_opener_seat');

select tests.act_as((select v from tests.fx where k = 'm2_opener'));
select auction.use_seal_token((select v from tests.fx where k = 'm2'));
select auction.submit_sealed_bid((select v from tests.fx where k = 'm2'), 5);
select tests.act_as((select v from tests.fx where k = 'm2_other'));
select auction.submit_sealed_bid((select v from tests.fx where k = 'm2'), 5);

select tests.act_as_admin();
select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm2') and seq = 1),
  (select v from tests.fx where k = 'm2_opener'),
  'a tie goes to whoever is closest to the opener seat'
);

-- ------------------------------------------------------------------ the deadline --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m3', tests.deal_and_open(2, 0.43));
insert into tests.fx (k, v) select 'm3_opener', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm3') and ap.seat = am.turn_seat;
select tests.act_as((select v from tests.fx where k = 'm3_opener'));
select auction.use_seal_token((select v from tests.fx where k = 'm3'));
select auction.submit_sealed_bid((select v from tests.fx where k = 'm3'), 9);

select tests.act_as_admin();
update public.auction_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm3');
select auction_private.expire((select v from tests.fx where k = 'm3'));

select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm3') and seq = 1),
  (select v from tests.fx where k = 'm3_opener'),
  'a missed deadline still resolves -- the one real bid beats an unsubmitted $0'
);
select is(
  (select price from public.auction_lots where match_id = (select v from tests.fx where k = 'm3') and seq = 1),
  9,
  'at the bid that was actually submitted'
);

-- ----------------------------------------------------------------- refusals --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m4', tests.deal_and_open(2, 0.44));
insert into tests.fx (k, v) select 'm4_opener', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm4') and ap.seat = am.turn_seat;

select tests.act_as((select v from tests.fx where k = 'm4_opener'));
select auction.place_bid((select v from tests.fx where k = 'm4'), 1);
select throws_ok(
  format($$ select auction.use_seal_token(%L) $$, (select v from tests.fx where k = 'm4')),
  'P0001', 'bidding_already_underway',
  'a lot cannot be sealed once someone has already bid on it'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m5', tests.deal_and_open(2, 0.45));
insert into tests.fx (k, v) select 'm5_opener', ap.user_id
  from public.auction_players ap join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm5') and ap.seat = am.turn_seat;
select tests.act_as((select v from tests.fx where k = 'm5_opener'));
select auction.use_seal_token((select v from tests.fx where k = 'm5'));
select auction.submit_sealed_bid((select v from tests.fx where k = 'm5'), 2);
select throws_ok(
  format($$ select auction.submit_sealed_bid(%L, 4) $$, (select v from tests.fx where k = 'm5')),
  'P0001', 'already_submitted',
  'a second submission from the same player is refused, not treated as a revision'
);

select throws_ok(
  format($$ select auction.submit_sealed_bid(%L, 999) $$, (select v from tests.fx where k = 'm1')),
  'P0001', 'sealed_bidding_not_open',
  'a lot that has already resolved refuses a late submission'
);

-- A lot only one player could ever win is moot to seal -- same reasoning as
-- the stuck-seat path in 0158, applied to a different mechanic.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m6', tests.deal(2, 0.46));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm6');
select auction_private.advance((select v from tests.fx where k = 'm6'));
update public.auction_lots set winner_id = (
         select ap.user_id from public.auction_players ap
          where ap.match_id = (select v from tests.fx where k = 'm6') and ap.seat = 1),
       slot = (select position from public.auction_lots
                where match_id = (select v from tests.fx where k = 'm6') and seq = 1)
 where match_id = (select v from tests.fx where k = 'm6')
   and seq = (select lot_count from public.auction_matches where match_id = (select v from tests.fx where k = 'm6'));
update public.auction_lots set winner_id = (
         select ap.user_id from public.auction_players ap
          where ap.match_id = (select v from tests.fx where k = 'm6') and ap.seat = 1),
       slot = 'FLEX'
 where match_id = (select v from tests.fx where k = 'm6')
   and seq = (select lot_count - 1 from public.auction_matches where match_id = (select v from tests.fx where k = 'm6'));
update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'm6');
select auction_private.expire((select v from tests.fx where k = 'm6'));
select tests.act_as((select ap.user_id from public.auction_players ap where ap.match_id = (select v from tests.fx where k = 'm6') and ap.seat = 0));
select throws_ok(
  format($$ select auction.use_seal_token(%L) $$, (select v from tests.fx where k = 'm6')),
  'P0001', 'seal_needs_two_bidders',
  'sealing a lot only one player is eligible for is refused -- it would never be a contest'
);

select * from finish();
rollback;
