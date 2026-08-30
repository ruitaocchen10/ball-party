-- The phase contract is observable through the same public state RPC that a
-- reconnecting client uses.  These are deliberate clock jumps: the server
-- validates every transition under its match-row lock.
begin;
select plan(29);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m', tests.deal(2, 0.77));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm');
select auction_private.advance((select v from tests.fx where k = 'm'));

select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 'lot_preview', 'a new lot begins in the shared preview phase');
select is((select turn_seat from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), null, 'preview has no actionable bidder');
select isnt((select phase_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), null, 'preview publishes a reconnectable deadline');

update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'm');
select auction_private.expire((select v from tests.fx where k = 'm'));
select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 'bidding', 'only the server advances the expired preview into bidding');
select isnt((select turn_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), null, 'live bidding receives the ten-second deadline');

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm')));
select auction.pass_lot((select v from tests.fx where k = 'm'));
select tests.act_as_admin();
select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 'sold', 'resolution enters sold before exposing another lot');
select is((select current_lot::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 1, 'sold keeps the resolved lot visible');
update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'm');
select auction_private.expire((select v from tests.fx where k = 'm'));
select is((select current_lot::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 2, 'sold expiry advances to the next preview');


-- ------------------------------------------------- automatic awards --------

-- A lot only one player can use is awarded without anybody acting. It still has
-- to earn a preview and a sold acknowledgement, or the rhythm breaks exactly
-- where the game is least able to explain itself.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('ma', tests.deal(2, 0.31));
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'ma');
select auction_private.advance((select v from tests.fx where k = 'ma'));

-- Fill the first lot's slot, and FLEX too, for one of the two seats, leaving a
-- single eligible bidder. Written onto different lots, so the lot under test
-- is untouched. Both have to close: since 0088, a full natural slot alone no
-- longer guarantees ineligibility (RB/WR/TE may still flex), so closing FLEX
-- as well is what keeps "only one eligible bidder" true regardless of which
-- position lot 1 happens to be.
update public.auction_lots set winner_id = (
         select ap.user_id from public.auction_players ap
          where ap.match_id = (select v from tests.fx where k = 'ma')
            and ap.seat = 1),
       slot = (select position from public.auction_lots
                where match_id = (select v from tests.fx where k = 'ma') and seq = 1)
 where match_id = (select v from tests.fx where k = 'ma')
   and seq = (select lot_count from public.auction_matches
               where match_id = (select v from tests.fx where k = 'ma'));

update public.auction_lots set winner_id = (
         select ap.user_id from public.auction_players ap
          where ap.match_id = (select v from tests.fx where k = 'ma')
            and ap.seat = 1),
       slot = 'FLEX'
 where match_id = (select v from tests.fx where k = 'ma')
   and seq = (select lot_count - 1 from public.auction_matches
               where match_id = (select v from tests.fx where k = 'ma'));

select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'ma')), 'lot_preview', 'a lot with one eligible bidder still opens in the shared preview');

update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'ma');
select auction_private.expire((select v from tests.fx where k = 'ma'));

select is((select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'ma') and seq = 1),
          (select ap.user_id from public.auction_players ap where ap.match_id = (select v from tests.fx where k = 'ma') and ap.seat = 0),
          'preview expiry awards the only eligible bidder');
select is((select price from public.auction_lots where match_id = (select v from tests.fx where k = 'ma') and seq = 1), 0, 'at the opening price of zero');
select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'ma')), 'sold', 'and holds a sold acknowledgement rather than opening bidding');
select is((select current_lot::int from public.auction_matches where match_id = (select v from tests.fx where k = 'ma')), 1, 'with the awarded lot still the current one');

-- ------------------------------------------- what a reconnect can read ------

-- The public read RPC is the whole reconnect story: a client that reloads mid
-- lot has to be told which phase is live and when it ends.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('mc', tests.deal(3, 0.55));
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'mc');
select auction_private.advance((select v from tests.fx where k = 'mc'));

select tests.act_as((select ap.user_id from public.auction_players ap
                      where ap.match_id = (select v from tests.fx where k = 'mc') and ap.seat = 0));
select is((select phase from auction.state((select v from tests.fx where k = 'mc'))), 'lot_preview', 'a reconnecting participant is told the shared phase');
select isnt((select phase_deadline from auction.state((select v from tests.fx where k = 'mc'))), null, 'and when that phase runs out');

select tests.act_as_admin();
update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'mc');
select auction_private.expire((select v from tests.fx where k = 'mc'));
select tests.act_as((select ap.user_id from public.auction_players ap
                      where ap.match_id = (select v from tests.fx where k = 'mc') and ap.seat = 0));
select is((select phase from auction.state((select v from tests.fx where k = 'mc'))), 'bidding', 'and the live phase once the server opens bidding');
select is((select phase_deadline from auction.state((select v from tests.fx where k = 'mc'))), null, 'where the turn deadline is the live clock and there is no phase deadline');

-- --------------------------------------- expiry only fires on a real one ----

-- Clients ask; the server decides. A deadline still in the future is refused in
-- every phase, which is what stops a fast or wrong client clock inventing one.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('me', tests.deal(3, 0.66));
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'me');
select auction_private.advance((select v from tests.fx where k = 'me'));
select ok(not auction_private.expire((select v from tests.fx where k = 'me')), 'a preview whose deadline has not passed is left alone');

update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'me');
select auction_private.expire((select v from tests.fx where k = 'me'));
select ok(not auction_private.expire((select v from tests.fx where k = 'me')), 'and a live bidding turn with time left on it is not auto-passed');

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'me')));
select auction.pass_lot((select v from tests.fx where k = 'me'));
select tests.act_as_admin();
select ok(not auction_private.expire((select v from tests.fx where k = 'me')), 'nor is a sold acknowledgement cut short');

-- ------------------------------------------------------- exact bids ---------

select tests.act_as_admin();
insert into tests.fx (k, v) values ('mx', tests.deal_and_open(4, 0.73));

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mx')));
select lives_ok(
  format($$ select auction.place_bid(%L, 1) $$, (select v from tests.fx where k = 'mx')),
  'the minimum legal bid -- one dollar over the opening price -- is accepted'
);
select tests.act_as_admin();
select is(tests.price((select v from tests.fx where k = 'mx')), 1, 'and lands as exactly that amount rather than an increment away from it');

-- The +$5 shortcut submits a derived exact amount, so it is the same contract.
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mx')));
select lives_ok(
  format($$ select auction.place_bid(%L, 6) $$, (select v from tests.fx where k = 'mx')),
  'the amount the +$5 shortcut derives is accepted through the same call'
);

select tests.act_as_admin();
update public.auction_players set budget = 9
 where match_id = (select v from tests.fx where k = 'mx')
   and user_id = tests.on_clock((select v from tests.fx where k = 'mx'));
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mx')));
select lives_ok(
  format($$ select auction.place_bid(%L, 9) $$, (select v from tests.fx where k = 'mx')),
  'a bid of the whole remaining budget is affordable'
);

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mx')));
select throws_ok(
  format($$ select auction.place_bid(%L, 10.5) $$, (select v from tests.fx where k = 'mx')),
  'P0001', 'bid_not_whole',
  'a fractional amount is refused for its shape rather than rounded into a legal one'
);

-- Eligibility is re-checked at the write, not merely used to pick the seat.
-- Both the natural slot and FLEX are closed for the same reason as in 'ma'
-- above: since 0088 a full natural slot alone does not guarantee
-- ineligibility for RB/WR/TE.
select tests.act_as_admin();
insert into tests.fx (k, v) select 'blocked', tests.on_clock((select v from tests.fx where k = 'mx'));
update public.auction_lots set winner_id = (select v from tests.fx where k = 'blocked'),
       slot = (select position from public.auction_lots
                where match_id = (select v from tests.fx where k = 'mx') and seq = 1)
 where match_id = (select v from tests.fx where k = 'mx')
   and seq = (select lot_count from public.auction_matches
               where match_id = (select v from tests.fx where k = 'mx'));
update public.auction_lots set winner_id = (select v from tests.fx where k = 'blocked'),
       slot = 'FLEX'
 where match_id = (select v from tests.fx where k = 'mx')
   and seq = (select lot_count - 1 from public.auction_matches
               where match_id = (select v from tests.fx where k = 'mx'));

select tests.act_as((select v from tests.fx where k = 'blocked'));
select throws_ok(
  format($$ select auction.place_bid(%L, 20) $$, (select v from tests.fx where k = 'mx')),
  'P0001', 'not_eligible',
  'a bidder with no open slot is refused even while on the clock'
);

-- The point of every rejection above: nothing about the lot moved.
select tests.act_as_admin();
select is((select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'mx') and seq = 1), null, 'a rejected bid leaves no sale behind');
select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'mx')), 'bidding', 'and leaves the last server-confirmed bidding state intact');
select is(tests.price((select v from tests.fx where k = 'mx')), 9, 'with the standing price untouched');

select * from finish();
rollback;
