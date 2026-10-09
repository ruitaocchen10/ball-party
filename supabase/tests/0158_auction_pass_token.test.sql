-- Pass token (0158): the sole live bidder on an uncontested lot gets a real
-- turn instead of an automatic $0 award, and may decline it with a token
-- instead of being forced to take it.
--
-- The decline's redraw is asserted directly here, not left to the fuzz
-- suite: a first version of this feature let a decline permanently destroy
-- one unit of that position's supply without ever filling anyone's roster
-- slot, which 0011/0020's stranding reports caught (QB and FLEX slots came
-- up short) once play_out started exercising stuck seats. Redrawing a
-- same-position replacement onto the end of the deck is what keeps total
-- supply exactly conserved, so this suite checks the redraw's effect
-- directly rather than only re-relying on the fuzzer to notice if it broke.

begin;
select plan(11);

\ir support/harness.psql

-- ------------------------------------------------------------- the stuck turn --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m1', tests.deal_and_open(2, 0.21));
insert into tests.fx (k, v) select 'm1_stuck', ap.user_id
  from public.auction_players ap
  join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm1') and ap.seat <> am.turn_seat;

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm1')));
select auction.pass_lot((select v from tests.fx where k = 'm1'));
select tests.act_as_admin();

select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  null,
  'the sole live bidder is not auto-awarded the lot'
);
select is(
  (select stuck_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm1')),
  (select turn_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm1')),
  'they are handed a real turn instead, as the stuck seat'
);
select is(
  (select used_pass_token from public.auction_players where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_stuck')),
  false,
  'merely being stuck costs nothing'
);

-- The free claim: taking it costs no token and resolves normally.
select tests.act_as((select v from tests.fx where k = 'm1_stuck'));
select auction.place_bid((select v from tests.fx where k = 'm1'), 0);
select tests.act_as_admin();

select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  (select v from tests.fx where k = 'm1_stuck'),
  'claiming it for $0 awards the stuck seat'
);
select is(
  (select used_pass_token from public.auction_players where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_stuck')),
  false,
  'and spends no token -- the free claim and the decline are different actions'
);

-- ------------------------------------------------------- the decline, and its redraw --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m2', tests.deal_and_open(2, 0.22));
insert into tests.num (k, v) select 'm2_lot_count', lot_count from public.auction_matches where match_id = (select v from tests.fx where k = 'm2');
insert into tests.fx (k, v) select 'm2_stuck', ap.user_id
  from public.auction_players ap
  join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm2') and ap.seat <> am.turn_seat;

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm2')));
select auction.pass_lot((select v from tests.fx where k = 'm2'));
select tests.act_as_admin();
select tests.act_as((select v from tests.fx where k = 'm2_stuck'));
select auction.pass_lot((select v from tests.fx where k = 'm2'));
select tests.act_as_admin();

select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm2') and seq = 1),
  null,
  'declining the stuck turn resolves to no sale'
);
select is(
  (select used_pass_token from public.auction_players where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_stuck')),
  true,
  'and spends their pass token'
);
select is(
  (select lot_count::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm2')),
  (select v::int from tests.num where k = 'm2_lot_count') + 1,
  'a declined lot redraws a replacement onto the end of the deck'
);
select is(
  (select position from public.auction_lots where match_id = (select v from tests.fx where k = 'm2') order by seq desc limit 1),
  (select position from public.auction_lots where match_id = (select v from tests.fx where k = 'm2') and seq = 1),
  'at the same position as the lot that was declined'
);

-- ------------------------------------------------------------- no tokens left --
-- (0170: a seat that cannot decline is not handed a stuck turn at all.)

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m3', tests.deal_and_open(2, 0.23, 'standard', 0::smallint));
insert into tests.fx (k, v) select 'm3_stuck', ap.user_id
  from public.auction_players ap
  join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm3') and ap.seat <> am.turn_seat;

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm3')));
select auction.pass_lot((select v from tests.fx where k = 'm3'));
select tests.act_as_admin();
select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'm3') and seq = 1),
  (select v from tests.fx where k = 'm3_stuck'),
  'with no token to spend there is nothing to decide, so the lot is awarded at once (0170), not after a 20s wait'
);
select is(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm3')),
  'sold',
  'and the lot is already resolved rather than waiting on a stuck turn'
);

select * from finish();
rollback;
