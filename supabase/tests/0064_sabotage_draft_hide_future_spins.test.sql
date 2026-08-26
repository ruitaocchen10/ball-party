-- Tests for hiding a round's spin until the table has actually reached it
-- (migration 0064). Reverses what 0051 and 0059 both argued on purpose --
-- see 0064's own header for why -- so this is the mirror image of 0059's
-- "the whole table can see which franchise every player is drafting from"
-- coverage: the current round stays exactly that open, but nothing ahead
-- of it is readable by anyone, including the row's own owner.

begin;
select plan(8);

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

select tests.act_as((select v from tests.fx where k = 'p0'));
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  3,
  'round 1''s spin is visible for every seated player the moment the match starts'
);
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm')
      and round_number = 1 and user_id = (select v::uuid from tests.fx where k = 'p1')),
  1,
  'including a teammate''s round-1 franchise -- the current round''s cross-seat visibility is unaffected'
);
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number > 1),
  0,
  'but nothing past the current round is -- not even the viewer''s own future spin'
);

select tests.act_as((select v from tests.fx where k = 'outsider'));
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm')),
  0,
  'and someone not seated at this table sees none of it, current round included'
);

-- -------------------------------------------------------- reaching round 2 --

-- Three players, three expired turns: exactly enough to close out round 1
-- without anyone submitting anything, the ordinary timeout path.
select tests.act_as_admin();
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select is(
  (select current_round::int from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  2,
  'three expired turns close out a three-player round 1, advancing the round'
);

select tests.act_as((select v from tests.fx where k = 'p0'));
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number <= 2),
  6,
  'round 2''s spin becomes readable the moment the table actually reaches it'
);
select is(
  (select count(*)::int from public.sabotage_draft_round_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number > 2),
  0,
  'round 3 onward stays exactly as hidden as round 2 just was'
);

select * from finish();
rollback;
