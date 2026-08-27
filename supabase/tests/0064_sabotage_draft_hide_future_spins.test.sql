-- Tests for hiding a round's spin until the table has actually reached it
-- (migration 0064), tightened by 0071 to gate on seat order too -- see its
-- header. The current round is no longer uniformly open the moment it
-- starts: only seats whose own turn has already been reached (seat <=
-- active_seat) are visible, same as an already-past round; a seat still
-- waiting its turn this round is exactly as hidden as a future round.

begin;
select plan(10);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));

select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm')),
  14 * 3,
  'the whole board -- all fourteen rounds, every seated player -- is dealt at match start, same as always'
);

-- -------------------------------------------------------------- round 1 --

-- Seat 0 (p0) is on the clock from deal -- active_seat defaults to 0.
select tests.act_as((select v from tests.fx where k = 'p0'));
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  1,
  'round 1''s spin is visible only for the seat whose turn has actually been reached -- just p0''s own, at deal time'
);
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm')
      and round_number = 1 and user_id = (select v::uuid from tests.fx where k = 'p1')),
  0,
  'a teammate two seats out this round is exactly as hidden as a future round -- their turn hasn''t come up yet'
);
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number > 1),
  0,
  'and nothing past the current round is visible either, same as before'
);

select tests.act_as((select v from tests.fx where k = 'outsider'));
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm')),
  0,
  'and someone not seated at this table sees none of it, current round included'
);

-- ------------------------------------------------------- p0's turn closes --

-- One expired turn: p0's pick-and-guess window times out, active_seat moves
-- to p1 without the round itself advancing.
select tests.act_as_admin();
select tests.sd_expire((select v from tests.fx where k = 'm'));

select tests.act_as((select v from tests.fx where k = 'p1'));
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  2,
  'once p1''s own turn is reached, round 1 opens up to seat 0 and seat 1 -- p1 can now see their own franchise too'
);
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm')
      and round_number = 1 and user_id = (select v::uuid from tests.fx where k = 'p2')),
  0,
  'but seat 2, still two turns out, stays hidden -- reaching the round is not the same as reaching the seat'
);

-- -------------------------------------------------------- reaching round 2 --

-- Two more expired turns: p1's and p2's, closing out round 1 the ordinary
-- timeout path (three seats, three turns, per round).
select tests.act_as_admin();
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select is(
  (select current_round::int from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  2,
  'three expired turns close out a three-player round 1, advancing the round and resetting active_seat to 0'
);

-- p0 is back on the clock for round 2 -- same seat-order gate applies there
-- as it did for round 1, on top of round 1 now being entirely in the past.
select tests.act_as((select v from tests.fx where k = 'p0'));
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number <= 2),
  4,
  'round 1 is now fully readable (3) plus just p0''s own round-2 spin (1) -- not every seat''s round 2 franchise yet'
);
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number > 2),
  0,
  'round 3 onward stays exactly as hidden as it was before'
);

select * from finish();
rollback;
