-- Tests for revealing a pick once its own round has closed (migration
-- 0069). Mirror image of 0064's "hide a future round's spin" coverage: the
-- current round stays exactly as concealed as 0052 made it, but nothing
-- behind it stays hidden from anyone seated at the table.

begin;
select plan(7);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));

select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- Three players, three expired turns: closes out round 1 entirely on
-- timeout, the fast path 0052's own test suite already uses for the same
-- reason -- nobody needs to have picked anything real for a pick's identity
-- to exist and be worth checking visibility on.
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select is(
  (select current_round::int from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  2,
  'three expired turns close out a three-player round 1, advancing the round'
);

-- --------------------------------------------------------- round 1, closed --

select tests.act_as((select v from tests.fx where k = 'p1'));
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  3,
  'every seat''s round-1 pick is now readable by any match member, not just its owner'
);
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm')
      and round_number = 1 and user_id = (select v::uuid from tests.fx where k = 'p0')),
  1,
  'including a teammate''s own round-1 identity, specifically'
);

select tests.act_as((select v from tests.fx where k = 'outsider'));
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  0,
  'but someone not seated at this table still sees none of it, closed round included'
);

-- ------------------------------------------------------- round 2, current --

-- One expired turn: closes out p0's own turn in round 2 without finishing
-- the round, so round 2 stays current while p0's pick already exists.
select tests.act_as_admin();
select tests.sd_expire((select v from tests.fx where k = 'm'));
select is(
  (select current_round::int from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  2,
  'round 2 has not closed -- only its first seat''s turn has'
);

select tests.act_as((select v from tests.fx where k = 'p1'));
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 2),
  0,
  'p0''s round-2 pick stays exactly as hidden from a teammate as 0052 made it -- the round is still open'
);
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  3,
  'round 1 stays readable regardless -- advancing round 2''s own turns does not re-hide it'
);

select * from finish();
rollback;
