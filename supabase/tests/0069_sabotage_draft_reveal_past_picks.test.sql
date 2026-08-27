-- Tests for revealing a pick once its own turn has resolved (migrations
-- 0069, restated by 0073 to draw the line at the turn rather than the whole
-- round). Mirror image of 0064/0071's "hide a future spin until the table
-- has actually reached it" coverage: a pick stays exactly as hidden as 0052
-- made it while its own turn is still live, but nothing whose guessing
-- window has actually closed stays hidden from anyone seated at the table.

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

-- --------------------------------------------------- round 2, turn still open --

-- p0 (seat 0) is active in round 2 and picks for real, but neither p1 nor
-- p2 has guessed or passed yet -- the turn has not resolved, so the pick
-- stays hidden exactly as 0052 made it, even though it now exists.
select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 2::smallint, (select v from tests.fx where k = 'p0'), 'RB') c;

select tests.act_as((select v from tests.fx where k = 'p1'));
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 2),
  0,
  'p0''s round-2 pick exists but stays hidden from a teammate while the turn''s own guessing window is still open'
);

-- ------------------------------------------------- round 2, turn resolved --

-- p1 and p2 both pass -- the turn's last two actions, resolving p0's turn
-- and handing the clock to p1, without closing out round 2 itself.
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_pass((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_pass((select v from tests.fx where k = 'm'));

select tests.act_as_admin();
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
  1,
  'p0''s round-2 pick is now readable by a teammate the moment p0''s own turn resolves -- the round itself staying open no longer matters'
);
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  3,
  'round 1 stays readable regardless -- resolving round 2''s first turn does not re-hide it'
);

select * from finish();
rollback;
