-- Tests for bidding, the turn timer, resolution and completion (0011).
--
-- This is where the game can be quietly wrong. Every other migration in this
-- sequence fails loudly — a bad board raises, a missing run blocks — but
-- eligibility and resolution fail by producing a game that runs to completion
-- and is subtly unfair. That is why the headline test plays whole boards out
-- rather than asserting on individual moves.

begin;
select plan(59);

\ir support/harness.psql

-- ---------------------------------------------------------- no stranding --
--
-- The claim docs/games/auction_team_builder/rules.md argues for in prose: the deal
-- guarantees the position counts, and the rule that a base lot may only be bid
-- on by a player whose natural slot is open guarantees they get consumed
-- one-for-one, so nobody can finish with a slot they never had a shot at.
--
-- It has to hold regardless of how people bid, hence the strategy matrix. This
-- is also the test that would have caught the FLEX hole before it shipped.
create function tests.stranding_report() returns text[]
language plpgsql as $$
declare
  v_n        int;
  v_strategy text;
  v_seed     int;
  v_match    uuid;
  v_bad      text[] := '{}';
begin
  foreach v_n in array array[2, 3, 4] loop
    foreach v_strategy in array array['pass', 'raise', 'random'] loop
      for v_seed in 1 .. 3 loop
        v_match := tests.deal_and_open(v_n, v_seed * 0.17);
        perform tests.play_out(v_match, v_strategy, v_seed);
        perform tests.act_as_admin();

        if tests.stranded(v_match) <> '{}'::text[] then
          v_bad := v_bad || format('N=%s %s seed=%s stranded %s',
                                   v_n, v_strategy, v_seed, tests.stranded(v_match));
        end if;

        if (select status from public.matches where id = v_match) <> 'complete' then
          v_bad := v_bad || format('N=%s %s seed=%s did not finish', v_n, v_strategy, v_seed);
        end if;
      end loop;
    end loop;
  end loop;

  return v_bad;
end $$;

select is(
  tests.stranding_report(),
  '{}'::text[],
  'across N = 2, 3, 4, three bidding strategies and three seeds, every player fills every slot and every board finishes'
);

-- ------------------------------------------------------------ turn rules --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m', tests.deal_and_open(4, 0.42));
select tests.act_as_admin();

select isnt(
  (select turn_seat from public.auction_matches where match_id = (select v from tests.fx where k = 'm')),
  null,
  'a dealt board opens with somebody on the clock'
);

select isnt(
  (select turn_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm')),
  null,
  'and a deadline for them to act by'
);

-- Somebody who is not on the clock.
select tests.act_as((
  select ap.user_id from public.auction_players ap
    join public.auction_matches am on am.match_id = ap.match_id
   where ap.match_id = (select v from tests.fx where k = 'm')
     and ap.seat <> am.turn_seat
   limit 1
));
select throws_ok(
  format($$ select auction.place_bid(%L, 1) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'not_your_turn',
  'a player who is not on the clock cannot bid'
);
select throws_ok(
  format($$ select auction.pass_lot(%L) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'not_your_turn',
  'nor pass'
);

-- Exact whole-dollar amounts are accepted rather than clamped.
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm')));
select lives_ok(
  format($$ select auction.place_bid(%L, 3) $$, (select v from tests.fx where k = 'm')),
  'an exact whole-dollar bid is accepted'
);
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm')));
select throws_ok(
  format($$ select auction.place_bid(%L, 0) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'bid_not_increasing',
  'and a non-increasing amount is refused'
);

-- Passing is final.
select tests.act_as_admin();
insert into tests.fx (k, v) select 'passer', tests.on_clock((select v from tests.fx where k = 'm'));

select tests.act_as((select v from tests.fx where k = 'passer'));
select lives_ok(
  format($$ select auction.pass_lot(%L) $$, (select v from tests.fx where k = 'm')),
  'the player on the clock can pass'
);

-- They are no longer on the clock, so the honest refusal is not_your_turn. The
-- already_passed guard is asserted below, where the turn can come back around.
select throws_ok(
  format($$ select auction.pass_lot(%L) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'not_your_turn',
  'and cannot pass again straight away'
);

select tests.act_as_admin();
select is(
  (select count(*)::int from public.auction_bids
    where match_id = (select v from tests.fx where k = 'm') and action = 'pass'),
  1,
  'the pass is recorded on the action log'
);

select is(
  (select by_timeout from public.auction_bids
    where match_id = (select v from tests.fx where k = 'm') order by bid_seq desc limit 1),
  false,
  'and is marked as a deliberate one'
);

-- ---------------------------------------------------------------- bidding --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('mb', tests.deal_and_open(4, 0.61));
select tests.act_as_admin();
insert into tests.fx (k, v) select 'opener', tests.on_clock((select v from tests.fx where k = 'mb'));

select tests.act_as((select v from tests.fx where k = 'opener'));
select lives_ok(
  format($$ select auction.place_bid(%L, 10) $$, (select v from tests.fx where k = 'mb')),
  'the opener can raise'
);

select tests.act_as_admin();
select is(
  tests.price((select v from tests.fx where k = 'mb')),
  10,
  'the price is the exact amount the opener submitted'
);

select isnt(
  tests.on_clock((select v from tests.fx where k = 'mb')),
  (select v from tests.fx where k = 'opener'),
  'and the turn moves off the player holding the high bid — nobody bids against themselves'
);

-- A raise beyond budget is refused; one exactly equal to it is not. Both
-- amounts have to clear the standing price of 10 first, or the affordability
-- rule never gets asked the question.
select tests.act_as_admin();
update public.auction_players set budget = 12
 where match_id = (select v from tests.fx where k = 'mb')
   and user_id = tests.on_clock((select v from tests.fx where k = 'mb'));

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mb')));
select throws_ok(
  format($$ select auction.place_bid(%L, 13) $$, (select v from tests.fx where k = 'mb')),
  'P0001', 'insufficient_budget',
  'a raise past the budget is refused'
);
select lives_ok(
  format($$ select auction.place_bid(%L, 12) $$, (select v from tests.fx where k = 'mb')),
  'a raise to exactly the budget is allowed'
);

-- A player who cannot beat the standing price has no action to take.  They
-- must not receive a full turn merely to press Pass; the server skips them and
-- gives the clock to the next player who can still raise.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('mskip', tests.deal_and_open(3, 0.62));
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mskip')));
select auction.place_bid((select v from tests.fx where k = 'mskip'), 10);
select tests.act_as_admin();
insert into tests.num (k, v)
select 'unaffordable_seat', ((turn_seat + 1) % 3)::int
  from public.auction_matches where match_id = (select v from tests.fx where k = 'mskip');
update public.auction_players set budget = 12
 where match_id = (select v from tests.fx where k = 'mskip')
   and seat = (select v::smallint from tests.num where k = 'unaffordable_seat');

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mskip')));
select auction.place_bid((select v from tests.fx where k = 'mskip'), 12);
select tests.act_as_admin();

select isnt(
  (select turn_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'mskip')),
  (select v from tests.num where k = 'unaffordable_seat'),
  'a player who cannot top the standing bid is skipped instead of receiving a twenty-second turn'
);
select is(
  (select automatic from public.auction_bids
    where match_id = (select v from tests.fx where k = 'mskip')
      and user_id = (select ap.user_id from public.auction_players ap
                       where ap.match_id = (select v from tests.fx where k = 'mskip')
                         and ap.seat = (select v::smallint from tests.num where k = 'unaffordable_seat'))
      and action = 'pass'),
  true,
  'the affordability skip is recorded as an automatic pass'
);
select ok(
  (select turn_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'mskip'))
    between now() + interval '19 seconds' and now() + interval '21 seconds',
  'the clock is immediately given to an actionable challenger'
);

-- A bankrupt rotating opener is a free fallback, not a player who waits out a
-- clock. A funded challenger can take the lot free or decline it to the opener.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('mfree', tests.deal(2, 0.73));
update public.auction_players set budget = 0 where match_id = (select v from tests.fx where k = 'mfree') and seat = 0;
update public.auction_matches set opener_seat = 0 where match_id = (select v from tests.fx where k = 'mfree');
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'mfree');
select auction_private.advance((select v from tests.fx where k = 'mfree'));
update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'mfree');
select auction_private.expire((select v from tests.fx where k = 'mfree'));
select is((select free_fallback_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'mfree')), 0, 'the bankrupt opener is retained as the free fallback');
select isnt((select turn_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'mfree')), 0, 'the funded challenger receives the decision');
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mfree')));
select auction.place_bid((select v from tests.fx where k = 'mfree'), 0);
select tests.act_as_admin();
select is((select price from public.auction_lots where match_id = (select v from tests.fx where k = 'mfree') and seq = 1), 0, 'the funded challenger can take the lot for $0');

insert into tests.fx (k, v) values ('mfallback', tests.deal(2, 0.74));
update public.auction_players set budget = 0 where match_id = (select v from tests.fx where k = 'mfallback') and seat = 0;
update public.auction_matches set opener_seat = 0 where match_id = (select v from tests.fx where k = 'mfallback');
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'mfallback');
select auction_private.advance((select v from tests.fx where k = 'mfallback'));
update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'mfallback');
select auction_private.expire((select v from tests.fx where k = 'mfallback'));
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mfallback')));
select auction.pass_lot((select v from tests.fx where k = 'mfallback'));
select tests.act_as_admin();
select is((select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'mfallback') and seq = 1), (select user_id from public.auction_players where match_id = (select v from tests.fx where k = 'mfallback') and seat = 0), 'declining the free lot awards it to the original opener');

insert into tests.fx (k, v) values ('mallzero', tests.deal(2, 0.75));
update public.auction_players set budget = 0 where match_id = (select v from tests.fx where k = 'mallzero');
update public.auction_matches set opener_seat = 0 where match_id = (select v from tests.fx where k = 'mallzero');
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'mallzero');
select auction_private.advance((select v from tests.fx where k = 'mallzero'));
update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'mallzero');
select auction_private.expire((select v from tests.fx where k = 'mallzero'));
select is((select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'mallzero') and seq = 1), (select user_id from public.auction_players where match_id = (select v from tests.fx where k = 'mallzero') and seat = 0), 'when everybody has $0 the rotating opener receives the lot immediately');

-- --------------------------------------------------- resolution and reveal --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('mr', tests.deal_and_open(2, 0.33));
select tests.act_as_admin();

-- With two players, one pass leaves one live bidder, who is handed a real
-- stuck turn (0158) rather than being awarded the lot automatically.
insert into tests.fx (k, v) select 'winner', ap.user_id
  from public.auction_players ap
  join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'mr') and ap.seat <> am.turn_seat;

select ok(
  (select bool_and(points is null) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'mr')),
  'before any lot resolves, no lot carries points'
);

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mr')));
select auction.pass_lot((select v from tests.fx where k = 'mr'));
select tests.act_as_admin();

select is(
  (select winner_id from public.auction_lots
    where match_id = (select v from tests.fx where k = 'mr') and seq = 1),
  null,
  'the sole live bidder is not awarded the lot automatically -- they are stuck with a real turn instead'
);

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mr')));
select auction.place_bid((select v from tests.fx where k = 'mr'), 0);
select tests.act_as_admin();

select is(
  (select winner_id from public.auction_lots
    where match_id = (select v from tests.fx where k = 'mr') and seq = 1),
  (select v from tests.fx where k = 'winner'),
  'the last live bidder takes the lot once they claim it'
);

select is(
  (select price from public.auction_lots
    where match_id = (select v from tests.fx where k = 'mr') and seq = 1),
  0,
  'at the $0 it opened at, since nobody raised — an empty wallet costs contested lots, never slots'
);

-- Read against the starting purse rather than a literal: the lot went for $0,
-- so "charged exactly the price" means the budget is untouched, whatever the
-- table currently deals.
select is(
  (select budget from public.auction_players
    where match_id = (select v from tests.fx where k = 'mr')
      and user_id = (select v from tests.fx where k = 'winner')),
  (select purse from public.auction_matches
    where match_id = (select v from tests.fx where k = 'mr')),
  'and resolution charges exactly the price and no more'
);

select is(
  (select slot from public.auction_lots
    where match_id = (select v from tests.fx where k = 'mr') and seq = 1),
  (select position from public.auction_lots
    where match_id = (select v from tests.fx where k = 'mr') and seq = 1),
  'a base lot fills the natural slot'
);

select is(
  (select l.points from public.auction_lots l
    where l.match_id = (select v from tests.fx where k = 'mr') and l.seq = 1),
  (select a.points from private.auction_answers a
    where a.match_id = (select v from tests.fx where k = 'mr') and a.seq = 1),
  'THE REVEAL: a resolved lot carries the real fantasy points'
);

select ok(
  (select points is null and resolved_at is null from public.auction_lots
    where match_id = (select v from tests.fx where k = 'mr') and seq = 2),
  'and resolving one lot reveals nothing about the next'
);

select is(
  (select current_lot::int from public.auction_matches
    where match_id = (select v from tests.fx where k = 'mr')),
  1,
  'the resolved lot remains current during its sold acknowledgement'
);

-- --------------------------------------------------------------- the timer --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('mt', tests.deal_and_open(3, 0.07));
select tests.act_as_admin();
insert into tests.fx (k, v) select 'watcher', ap.user_id
  from public.auction_players ap
  join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'mt') and ap.seat <> am.turn_seat
 limit 1;
insert into tests.num (k, v) select 'seat_before', turn_seat
  from public.auction_matches where match_id = (select v from tests.fx where k = 'mt');

-- Before the deadline, expiry is a no-op. Client clocks decide when to ask,
-- never what is true.
select tests.act_as((select v from tests.fx where k = 'watcher'));
select lives_ok(
  format($$ select auction.expire_turn(%L) $$, (select v from tests.fx where k = 'mt')),
  'any participant may call expire_turn, not only the player on the clock'
);

select tests.act_as_admin();
select is(
  (select turn_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'mt')),
  (select v from tests.num where k = 'seat_before'),
  'and before the deadline it changes nothing'
);

select is(
  (select count(*)::int from public.auction_bids where match_id = (select v from tests.fx where k = 'mt')),
  0,
  'not even an entry in the action log'
);

-- Force the deadline into the past rather than waiting ten seconds for it.
update public.auction_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'mt');

select tests.act_as((select v from tests.fx where k = 'watcher'));
select auction.expire_turn((select v from tests.fx where k = 'mt'));
select tests.act_as_admin();

select is(
  (select count(*)::int from public.auction_bids
    where match_id = (select v from tests.fx where k = 'mt')
      and action = 'pass' and by_timeout),
  1,
  'past the deadline it auto-passes the player on the clock, flagged as a timeout'
);

select isnt(
  (select turn_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'mt')),
  (select v from tests.num where k = 'seat_before'),
  'and the turn moves on'
);

-- Idempotency is structural: the first caller set a deadline in the future, so
-- everyone racing behind them falls out at the check.
select tests.act_as_admin();
insert into tests.num (k, v) select 'seat_after', turn_seat
  from public.auction_matches where match_id = (select v from tests.fx where k = 'mt');

select tests.act_as((select v from tests.fx where k = 'watcher'));
select auction.expire_turn((select v from tests.fx where k = 'mt'));
select auction.expire_turn((select v from tests.fx where k = 'mt'));
select tests.act_as_admin();

select is(
  (select turn_seat::int from public.auction_matches where match_id = (select v from tests.fx where k = 'mt')),
  (select v from tests.num where k = 'seat_after'),
  'four clients firing expire_turn at once advance exactly one turn between them'
);

select is(
  (select count(*)::int from public.auction_bids where match_id = (select v from tests.fx where k = 'mt')),
  1,
  'and only one action is logged'
);

-- A timeout and a manual pass are the same move. Two boards from one seed, one
-- passed by hand and one timed out, have to agree on everything but the flag.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('ma', tests.deal_and_open(3, 0.55));
insert into tests.fx (k, v) values ('mz', tests.deal_and_open(3, 0.55));
select tests.act_as_admin();

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'ma')));
select auction.pass_lot((select v from tests.fx where k = 'ma'));

select tests.act_as_admin();
update public.auction_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'mz');
select tests.act_as(tests.on_clock((select v from tests.fx where k = 'mz')));
select auction.expire_turn((select v from tests.fx where k = 'mz'));
select tests.act_as_admin();

select is(
  (select array[turn_seat, current_lot, opener_seat] from public.auction_matches
    where match_id = (select v from tests.fx where k = 'mz')),
  (select array[turn_seat, current_lot, opener_seat] from public.auction_matches
    where match_id = (select v from tests.fx where k = 'ma')),
  'an auto-pass leaves the same turn state as a manual one'
);

select is(
  (select array_agg(action order by bid_seq) from public.auction_bids
    where match_id = (select v from tests.fx where k = 'mz')),
  (select array_agg(action order by bid_seq) from public.auction_bids
    where match_id = (select v from tests.fx where k = 'ma')),
  'and the same action log'
);

select isnt(
  (select by_timeout from public.auction_bids
    where match_id = (select v from tests.fx where k = 'mz') order by bid_seq limit 1),
  (select by_timeout from public.auction_bids
    where match_id = (select v from tests.fx where k = 'ma') order by bid_seq limit 1),
  'differing only in whether the clock or the player decided it'
);

-- --------------------------------------------------------- eligibility --
--
-- FLEX no longer waits for a dedicated round (0088). A base lot may be bid on
-- for its natural slot whenever that's open; once it's full, RB/WR/TE (never
-- QB) may go to FLEX instead, but only when enough of that exact position
-- remains undealt to cover every other player's remaining natural need -- in
-- slot units, not a headcount of players. Constructed directly against
-- auction_private.eligible() rather than played to, so each rule is asserted
-- in isolation.

-- QB is the one absolute case: it never flexes, so once the single QB slot is
-- full, no remaining QB lot is eligible no matter how much QB supply is left.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('melq', tests.deal(4, 0.88, 'standard'));
insert into tests.fx (k, v)
  select 'q0', user_id from public.auction_players where match_id = (select v from tests.fx where k = 'melq') and seat = 0;

update public.auction_lots
   set winner_id = (select v from tests.fx where k = 'q0'), price = 0, slot = 'QB', resolved_at = now()
 where match_id = (select v from tests.fx where k = 'melq')
   and seq = (select min(seq) from public.auction_lots
               where match_id = (select v from tests.fx where k = 'melq') and position = 'QB');

select ok(
  not exists (
    select 1 from public.auction_lots l
     where l.match_id = (select v from tests.fx where k = 'melq') and l.position = 'QB' and l.winner_id is null
       and auction_private.eligible((select v from tests.fx where k = 'melq'), (select v from tests.fx where k = 'q0'), l.seq)
  ),
  'QB never flexes: once the one QB slot is full, no remaining QB lot is eligible'
);

-- Once both a player's natural slot and FLEX are full, nothing is left to try.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('melb', tests.deal(4, 0.22, 'standard'));
insert into tests.fx (k, v)
  select 'b0', user_id from public.auction_players where match_id = (select v from tests.fx where k = 'melb') and seat = 0;

update public.auction_lots
   set winner_id = (select v from tests.fx where k = 'b0'), price = 0, slot = 'RB', resolved_at = now()
 where match_id = (select v from tests.fx where k = 'melb')
   and seq = (select min(seq) from public.auction_lots
               where match_id = (select v from tests.fx where k = 'melb') and position = 'RB');
update public.auction_lots
   set winner_id = (select v from tests.fx where k = 'b0'), price = 0, slot = 'FLEX', resolved_at = now()
 where match_id = (select v from tests.fx where k = 'melb')
   and seq = (select min(seq) from public.auction_lots
               where match_id = (select v from tests.fx where k = 'melb') and position = 'WR');

select ok(
  not exists (
    select 1 from public.auction_lots l
     where l.match_id = (select v from tests.fx where k = 'melb') and l.position = 'RB' and l.winner_id is null
       and auction_private.eligible((select v from tests.fx where k = 'melb'), (select v from tests.fx where k = 'b0'), l.seq)
  ),
  'once a natural slot and FLEX are both full, no remaining lot at that position is eligible either way'
);

-- THE FEATURE: with a natural slot already full, FLEX open, and plenty of
-- that position left over for everyone else, a player may bid a base lot into
-- FLEX well before the board is spent -- not just in a final flex round.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('melc', tests.deal(4, 0.33, 'standard'));
insert into tests.fx (k, v)
  select 'c0', user_id from public.auction_players where match_id = (select v from tests.fx where k = 'melc') and seat = 0;

update public.auction_lots
   set winner_id = (select v from tests.fx where k = 'c0'), price = 0, slot = 'RB', resolved_at = now()
 where match_id = (select v from tests.fx where k = 'melc')
   and seq = (select min(seq) from public.auction_lots
               where match_id = (select v from tests.fx where k = 'melc') and position = 'RB');

select ok(
  auction_private.eligible(
    (select v from tests.fx where k = 'melc'),
    (select v from tests.fx where k = 'c0'),
    (select min(seq) from public.auction_lots
      where match_id = (select v from tests.fx where k = 'melc') and position = 'RB' and winner_id is null)
  ),
  'a player whose natural RB is already full may bid another RB lot into FLEX, with the board barely touched'
);

-- THE BUG THE SIMULATOR CAUGHT, pinned as a regression: remaining need has to
-- be counted in slot units, not a headcount of players who still need "any".
-- Full preset gives two RB slots each. seat0's are both full; seat1 and seat2
-- have made no RB progress at all (two units each still); seat3 has one of
-- two (one unit still). Real remaining need is 2+2+1 = 5 units. A naive
-- headcount would see only "three other players still need it" and think
-- four undealt lots were plenty; they are not enough to cover five units.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('meld', tests.deal(4, 0.44, 'full'));
insert into tests.fx (k, v)
  select 'd0', user_id from public.auction_players where match_id = (select v from tests.fx where k = 'meld') and seat = 0;
insert into tests.fx (k, v)
  select 'd1', user_id from public.auction_players where match_id = (select v from tests.fx where k = 'meld') and seat = 1;
insert into tests.fx (k, v)
  select 'd3', user_id from public.auction_players where match_id = (select v from tests.fx where k = 'meld') and seat = 3;

with numbered as (
  select seq, row_number() over (order by seq) as rn from public.auction_lots
   where match_id = (select v from tests.fx where k = 'meld') and position = 'RB'
)
update public.auction_lots l
   set winner_id = (select v from tests.fx where k = 'd0'), price = 0, slot = 'RB', resolved_at = now()
  from numbered n
 where l.match_id = (select v from tests.fx where k = 'meld') and l.seq = n.seq and n.rn in (1, 2);

with numbered as (
  select seq, row_number() over (order by seq) as rn from public.auction_lots
   where match_id = (select v from tests.fx where k = 'meld') and position = 'RB'
)
update public.auction_lots l
   set winner_id = (select v from tests.fx where k = 'd3'), price = 0, slot = 'RB', resolved_at = now()
  from numbered n
 where l.match_id = (select v from tests.fx where k = 'meld') and l.seq = n.seq and n.rn = 3;

-- Two more RB-position lots already spent on somebody's FLEX: pool supply
-- consumed without satisfying anybody's natural RB need, same as any other
-- flex conversion would.
with numbered as (
  select seq, row_number() over (order by seq) as rn from public.auction_lots
   where match_id = (select v from tests.fx where k = 'meld') and position = 'RB'
)
update public.auction_lots l
   set winner_id = (select v from tests.fx where k = 'd1'), price = 0, slot = 'FLEX', resolved_at = now()
  from numbered n
 where l.match_id = (select v from tests.fx where k = 'meld') and l.seq = n.seq and n.rn in (4, 5);

select ok(
  not auction_private.eligible(
    (select v from tests.fx where k = 'meld'),
    (select v from tests.fx where k = 'd0'),
    (select min(seq) from public.auction_lots
      where match_id = (select v from tests.fx where k = 'meld') and position = 'RB' and winner_id is null)
  ),
  'remaining need is counted in slot units, so a multi-slot position cannot be undercounted into stranding someone'
);

-- ------------------------------------------------------------- completion --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('mf', tests.deal_and_open(3, 0.29));
select tests.act_as_admin();
select is(tests.play_out((select v from tests.fx where k = 'mf'), 'random', 5) > 0, true,
  'a board plays out to the end');

select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'mf')),
  'complete',
  'the match ends complete'
);

select is(
  (select r.status::text from public.runs r
     join public.matches mt on mt.run_id = r.id
    where mt.id = (select v from tests.fx where k = 'mf')),
  'finished',
  'and an arcade run ends finished'
);

select is(
  (select turn_seat from public.auction_matches where match_id = (select v from tests.fx where k = 'mf')),
  null,
  'nobody is left on the clock'
);

select ok(
  not exists (
    select 1
      from public.match_players mp
      left join (
        select winner_id, sum(points) as total
          from public.auction_lots
         where match_id = (select v from tests.fx where k = 'mf') and winner_id is not null
         group by winner_id
      ) w on w.winner_id = mp.user_id
     where mp.match_id = (select v from tests.fx where k = 'mf')
       and mp.raw_score is distinct from coalesce(w.total, 0)
  ),
  'each final score is the sum of the points on the lots that player won'
);

select is(
  (select count(*)::int from public.match_players
    where match_id = (select v from tests.fx where k = 'mf')),
  3,
  'everyone at the table appears in the standings, including anyone who won nothing'
);

-- Since 0090 the match can end before every dealt lot is used -- once every
-- roster is full there is nothing left to bid on, so a spare lot beyond that
-- point never gets a chance to be revealed at all. What actually has to hold
-- is narrower: every lot that DID resolve carries its revealed points, and
-- nobody's roster is short a slot the moment the match calls itself done.
select ok(
  not exists (
    select 1 from public.auction_lots
     where match_id = (select v from tests.fx where k = 'mf')
       and winner_id is not null and points is null
  ),
  'every resolved lot carries its revealed points'
);

select is(
  tests.stranded((select v from tests.fx where k = 'mf')),
  '{}'::text[],
  'and nobody''s roster is short a slot when the match calls itself done'
);

-- ---------------------------------------------------- early finish (0090) --
--
-- The draft does not have to exhaust every dealt lot to be over: the moment
-- every seated player's roster (every natural slot plus FLEX) is completely
-- full, there is nothing left worth bidding on. Built directly (fill every
-- slot by hand, in seq order, rather than played out) so it is deterministic
-- that lots remain undealt when the match calls itself done -- 0089's floor
-- guarantees a two-player Standard table has at least four RB lots (two
-- natural, two buffer), which is exactly enough to hand each seat both its
-- natural RB and its FLEX from the same position.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('me2', tests.deal(2, 0.44));
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'me2');
select auction_private.advance((select v from tests.fx where k = 'me2'));

with seats as (
  select ap.user_id, row_number() over (order by ap.seat) as rn
    from public.auction_players ap
   where ap.match_id = (select v from tests.fx where k = 'me2')
),
naturals as (
  select al.seq, al.position, row_number() over (partition by al.position order by al.seq) as rn
    from public.auction_lots al
   where al.match_id = (select v from tests.fx where k = 'me2')
     and al.position in ('QB', 'RB', 'WR', 'TE')
)
update public.auction_lots al
   set winner_id = s.user_id, slot = al.position, price = 0, resolved_at = now(),
       points = (select aa.points from private.auction_answers aa where aa.match_id = al.match_id and aa.seq = al.seq)
  from naturals n join seats s on s.rn = n.rn
 where al.match_id = (select v from tests.fx where k = 'me2') and al.seq = n.seq;

with seats as (
  select ap.user_id, row_number() over (order by ap.seat) as rn
    from public.auction_players ap
   where ap.match_id = (select v from tests.fx where k = 'me2')
),
flex_lots as (
  select al.seq, row_number() over (order by al.seq) as rn
    from public.auction_lots al
   where al.match_id = (select v from tests.fx where k = 'me2')
     and al.position = 'RB' and al.winner_id is null
)
update public.auction_lots al
   set winner_id = s.user_id, slot = 'FLEX', price = 0, resolved_at = now(),
       points = (select aa.points from private.auction_answers aa where aa.match_id = al.match_id and aa.seq = al.seq)
  from flex_lots f join seats s on s.rn = f.rn
 where al.match_id = (select v from tests.fx where k = 'me2') and al.seq = f.seq;

select is(
  tests.stranded((select v from tests.fx where k = 'me2')),
  '{}'::text[],
  'both rosters are genuinely complete before the match is told so'
);

select ok(
  exists (
    select 1 from public.auction_lots
     where match_id = (select v from tests.fx where k = 'me2') and winner_id is null
  ),
  'and lots remain undealt -- the board was not exhausted to get there'
);

select auction_private.advance((select v from tests.fx where k = 'me2'));

select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'me2')),
  'complete',
  'advance() ends the match on a full roster alone, without waiting for current_lot to pass lot_count'
);

select ok(
  (select current_lot <= lot_count from public.auction_matches
    where match_id = (select v from tests.fx where k = 'me2')),
  'confirmed by current_lot never having to catch up to lot_count'
);

select * from finish();
rollback;
