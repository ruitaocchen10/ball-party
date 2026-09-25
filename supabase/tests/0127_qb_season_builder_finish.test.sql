-- Tests for QB Season Builder's finish: turning six picked values into a saved,
-- shareable season (issue #77, sub-issue of #72). Migration 0127.
--
-- Everything is asserted through the game's public calls, as a player, a guest or
-- a signed-out visitor would make them. The season model is replaced by a small
-- one of our own (tests.qsb_model_fixtures) whose every number can be worked out
-- by hand, so retuning the fitted model can never break a test here. Where a test
-- needs a fixed seed it goes through the private finisher, the way the auction's
-- tests deal from a fixed seed: the public call takes none, on purpose.

begin;
select plan(68);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina')),
       ('stranger', tests.mkuser('sten'));

select tests.act_as_admin();
select tests.qsb_fixtures();
-- Migration 0128 draws every spin from a team-season not yet shown in the run, so a
-- run of six needs a pool of at least seven. The shared fixtures have five; these two
-- keep the pool from running dry when a test steers the spins by hand.
insert into qb_season_builder_private.team_seasons (franchise_code, season, supporting_cast)
values ('gnb', 2011, 87), ('sea', 2015, 78);
insert into qb_season_builder_private.qb_seasons
  (franchise_code, season, player_id, display_name, accuracy, arm_talent, mobility, iq, build)
values
  ('gnb', 2011, 'RodgAa00', 'Aaron Rodgers', 98, 96, 92, 98, 39),
  ('sea', 2015, 'WilsRu00', 'Russell Wilson', 93, 83, 91, 87, 62);
select tests.qsb_model_fixtures();

-- ------------------------------------------------------------------ finishing --

insert into tests.fx (k, v)
select 'r', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.qsb_fill((select v from tests.fx where k = 'r'), 5);

select throws_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'r')),
  'P0001', 'draft_incomplete',
  'a run with a slot still open cannot be finished'
);
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'r')),
  'playing',
  'and is left as it was'
);

select tests.qsb_set_spin((select v from tests.fx where k = 'r'), 6::smallint, 'phi', 2017::smallint);
select qb_season_builder.pick((select v from tests.fx where k = 'r'), 'supporting_cast');

select lives_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'r')),
  'with all six slots filled the run can be finished'
);
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'r')),
  'complete',
  'and it is then a completed match'
);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) ->> 'match_id'),
  (select v::text from tests.fx where k = 'r'),
  'and has a saved result'
);

-- ------------------------------------------------------------------ the season --

-- Run 'r' picked 87 accuracy, 90 arm talent, 79 mobility, 83 IQ, 86 build and a
-- Supporting Cast of 69. Through the fixture model (see tests.qsb_model_fixtures)
-- that is 374 attempts at 74.8%, 11 yards each, 8.3% touchdowns, 1.7% picks,
-- 790 yards and 7.9 touchdowns on the ground, and 13.8 wins.
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'stat_line'),
  '{"attempts": 374, "completions": 280, "pass_yards": 4114, "pass_tds": 31,
    "interceptions": 6, "rating": 130.8, "rush_yards": 790, "rush_tds": 8}'::jsonb,
  'the season has the full stat line: passing, interceptions, rating and rushing'
);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'record'),
  '{"wins": 14, "losses": 3}'::jsonb,
  'a record over a 17-game season'
);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'playoffs'),
  '{"depth": 5, "result": "won_super_bowl"}'::jsonb,
  'and a playoff result'
);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'awards'),
  '{"mvp": true, "opoy": false, "all_pro": true, "pro_bowl": true, "sb_mvp": true}'::jsonb,
  'and the five awards, Super Bowl MVP included because the team won the title'
);
-- stat line 1.114 z: better than 4 of 5 real seasons; team success 3.0: 2 of 5;
-- awards 12 points: all 5. 50 x 0.8 + 30 x 0.4 + 20 x 1.0 = 72.
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'score'),
  '72.0'::jsonb,
  'a score out of 100'
);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'breakdown'),
  '[{"component": "stat_line",    "weight": 50, "percentile": 0.8, "points": 40.0},
    {"component": "team_success", "weight": 30, "percentile": 0.4, "points": 12.0},
    {"component": "awards",       "weight": 20, "percentile": 1.0, "points": 20.0}]'::jsonb,
  'and a breakdown of what drove it'
);
select is(
  (select jsonb_path_query_array(qb_season_builder.result((select v from tests.fx where k = 'r')), '$.picks[*].slot')),
  '["accuracy", "arm_talent", "mobility", "iq", "build", "supporting_cast"]'::jsonb,
  'with a recap of the six picks'
);

select throws_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'r')),
  'P0001', 'match_not_playing',
  'a run cannot be finished twice'
);

select tests.act_as_admin();
select is(
  (select count(*)::int from qb_season_builder_private.season_results
    where match_id = (select v from tests.fx where k = 'r')),
  1,
  'one run has exactly one saved result'
);

insert into tests.fx (k, v)
select 'other', tests.mksolomatch((select v from tests.fx where k = 'a'), 'higher_or_lower');
select throws_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'other')),
  'P0001', 'wrong_game',
  'a run of another game cannot be finished as this one'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'r')),
  '42501', 'not_a_participant',
  'nor by a player who is not in it'
);
select throws_ok(
  format($$ select qb_season_builder.finish(%L) $$, gen_random_uuid()),
  'P0002', 'match_not_found',
  'nor a run that does not exist'
);

select tests.act_as_admin();
select set_config('request.jwt.claims', '', true);
select set_config('role', 'authenticated', true);
select throws_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'r')),
  '42501', 'not_authenticated',
  'nor with no session'
);

-- ---------------------------------------------------------- seed and randomness --

-- Noise on everything and a coin flip at every playoff rung and award edge, so a
-- seed has something to decide.
select tests.qsb_model_fixtures(p_wins_noise := 1, p_line_noise := 0, p_award_noise := 1, p_ladder := 0);

insert into tests.fx (k, v)
select 'same1', tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), 7);
insert into tests.fx (k, v)
select 'same2', tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), 7);

select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'same1')) - 'match_id'),
  (select qb_season_builder.result((select v from tests.fx where k = 'same2')) - 'match_id'),
  'the same picks and the same seed give the same season'
);

create temp table seeded (seed int, match_id uuid);
grant all on seeded to public;
insert into seeded (seed, match_id)
select s, tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), s)
  from generate_series(1, 12) s;

select cmp_ok(
  (select count(distinct qb_season_builder.result(match_id) -> 'record')::int from seeded), '>', 1,
  'but a different seed gives a different season'
);
select ok(
  (select bool_and((qb_season_builder.result(match_id) -> 'record' ->> 'wins')::int between 12 and 16)
     from seeded),
  'and the luck is bounded: 13.8 expected wins, a real miss of 2 either way, never further'
);
select is(
  (select count(distinct qb_season_builder.result(match_id) -> 'stat_line' ->> 'pass_yards')::int from seeded),
  1,
  'and it lands on the team outcome, not the quarterback''s own line, when that has no noise'
);

select tests.qsb_model_fixtures(p_wins_noise := 0, p_line_noise := 1);
delete from seeded;
insert into seeded (seed, match_id)
select s, tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), s)
  from generate_series(1, 12) s;

select ok(
  (select count(distinct qb_season_builder.result(match_id) -> 'stat_line' ->> 'attempts') > 1
      and bool_and((qb_season_builder.result(match_id) -> 'stat_line' ->> 'attempts')::int between 334 and 414)
     from seeded),
  'a quarterback line with noise moves with the seed, within the real spread around 374 attempts'
);

-- ------------------------------------------------- playoffs, awards and the score --

-- A ladder no rung of which can be cleared: the team misses the playoffs, and the
-- Super Bowl MVP, whose score this season clears, is not awarded without the title.
select tests.qsb_model_fixtures(p_ladder := -50);
insert into tests.fx (k, v)
select 'miss', tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), 1);

select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'miss')) -> 'playoffs'),
  '{"depth": 0, "result": "missed_playoffs"}'::jsonb,
  'a team that clears no rung of the playoff ladder misses the playoffs'
);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'miss')) -> 'awards' -> 'sb_mvp'),
  'false'::jsonb,
  'and cannot be Super Bowl MVP, however good the season'
);

-- Wins 14 give an MVP score 0.5 clear of its threshold, Offensive Player of the
-- Year 0.39 short of its, and All-Pro 0.11 clear of its. Each award's edge moves by
-- at most half its spread (0.5 x 0.5 = 0.25) either way, so the first is earned
-- whatever the seed, the second never, and the third only sometimes.
select tests.qsb_model_fixtures(p_award_noise := 0.5);
delete from seeded;
insert into seeded (seed, match_id)
select s, tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), s)
  from generate_series(1, 12) s;

select ok(
  (select bool_and((qb_season_builder.result(match_id) -> 'awards' ->> 'mvp')::boolean) from seeded),
  'an award well clear of its threshold is earned whatever the seed'
);
select ok(
  (select not bool_or((qb_season_builder.result(match_id) -> 'awards' ->> 'opoy')::boolean) from seeded),
  'one well short of it never is'
);
select ok(
  (select bool_or((qb_season_builder.result(match_id) -> 'awards' ->> 'all_pro')::boolean)
      and not bool_and((qb_season_builder.result(match_id) -> 'awards' ->> 'all_pro')::boolean)
     from seeded),
  'and one near it depends on the seed'
);

-- Better than every real season on every component is 100, and not more.
select tests.qsb_model_fixtures();
update qb_season_builder_private.season_model_distributions set value = value - 100;
insert into tests.fx (k, v)
select 'best', tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), 1);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'best')) -> 'score'),
  '100.0'::jsonb,
  'a season better than every real one scores exactly 100'
);

-- Better than none of them is 0.
update qb_season_builder_private.season_model_distributions set value = value + 200;
insert into tests.fx (k, v)
select 'worst', tests.qsb_finish_with_seed((select v from tests.fx where k = 'a'), 1);
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'worst')) -> 'score'),
  '0.0'::jsonb,
  'and one better than none scores 0'
);

-- The platform's own record of the match carries the score.
select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select raw_score from public.match_players where match_id = (select v from tests.fx where k = 'best')),
  100.0,
  'the finished match records the score for the player'
);
select tests.act_as_admin();

-- ------------------------------------------------------------ the hidden reveal --

select tests.qsb_model_fixtures();

-- A hidden run that spends its respin on round 1 and passes on Matt Moore in
-- round 3. Six spins are taken, and seven were shown.
insert into tests.fx (k, v)
select 'hid', tests.qsb_start((select v from tests.fx where k = 'a'), 'hidden');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'hid'), 1::smallint, 'kan', 2019::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.respin((select v from tests.fx where k = 'hid'));
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'hid'), 1::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'hid'), 'accuracy', 'WentCa00');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'hid'), 2::smallint, 'nwe', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'hid'), 'arm_talent', 'BradTo00');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'hid'), 3::smallint, 'kan', 2019::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'hid'), 'mobility', 'MahoPa00');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'hid'), 4::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'hid'), 'iq', 'WentCa00');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'hid'), 5::smallint, 'kan', 2018::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'hid'), 'build', 'MahoPa00');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'hid'), 6::smallint, 'nwe', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'hid'), 'supporting_cast');

select is(
  (select shown from qb_season_builder.state((select v from tests.fx where k = 'hid'))),
  null,
  'with all six slots filled, a hidden run has still been shown nothing it passed on'
);

select qb_season_builder.finish((select v from tests.fx where k = 'hid'));

select is(
  (select phase from qb_season_builder.state((select v from tests.fx where k = 'hid'))),
  'complete',
  'a finished run reads as complete'
);
select is(
  (select jsonb_array_length(shown) from qb_season_builder.state((select v from tests.fx where k = 'hid'))),
  7,
  'and reveals every spin the player was shown, the respun-away one included'
);
select is(
  (select jsonb_path_query_array(shown, '$[*] ? (@.round == 1).franchise_code')
     from qb_season_builder.state((select v from tests.fx where k = 'hid'))),
  '["kan", "phi"]'::jsonb,
  'the respun round shows both attempts, oldest first'
);
select is(
  (select jsonb_path_query_array(
            shown, '$[*] ? (@.round == 3).options.quarterbacks[*] ? (@.player_id == "MoorMa00").grades.accuracy')
     from qb_season_builder.state((select v from tests.fx where k = 'hid'))),
  '["C-"]'::jsonb,
  'with the grades of the quarterback who was passed on'
);
select is(
  (select count(*)::int
     from qb_season_builder.state((select v from tests.fx where k = 'hid')) b,
          jsonb_array_elements(b.shown) s,
          jsonb_array_elements(s -> 'options' -> 'quarterbacks') q
    where jsonb_typeof(q -> 'grades') <> 'object'),
  0,
  'and of every other option, none of them still hidden'
);
select is(
  (select count(*)::int
     from qb_season_builder.state((select v from tests.fx where k = 'hid')) b,
          jsonb_array_elements(b.shown) s
    where jsonb_typeof(s -> 'options' -> 'supporting_cast' -> 'grade') <> 'string'),
  0,
  'the Supporting Cast of every spin as well'
);
select is(
  (select jsonb_path_query_array(picks, '$[*].grade')
     from qb_season_builder.state((select v from tests.fx where k = 'hid'))),
  '["A-", "B+", "B+", "B+", "B-", "B-"]'::jsonb,
  'and the grade of every pick'
);

-- -------------------------------------------------------- the public result path --

-- 'r' was finished long ago under a model that has since been replaced twice: the
-- saved result is what it was, not a recomputation.
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'notyet', tests.qsb_start((select v from tests.fx where k = 'a'));
insert into tests.fx (k, v)
select 'gr', tests.qsb_start((select v from tests.fx where k = 'guest'), 'visible', true);
select tests.qsb_fill((select v from tests.fx where k = 'gr'), 6);
select qb_season_builder.finish((select v from tests.fx where k = 'gr'));
select tests.act_as_admin();

set local role anon;
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'score'),
  '72.0'::jsonb,
  'a signed-out visitor with the link can read a result, as it was saved'
);
select is(
  (select jsonb_path_query_array(qb_season_builder.result((select v from tests.fx where k = 'gr')), '$.picks[*].display_name')
     -> 0),
  '"Carson Wentz"'::jsonb,
  'including a guest''s'
);
select is(
  (select jsonb_path_query_array(qb_season_builder.result((select v from tests.fx where k = 'hid')), '$.picks[*].franchise_code')),
  '["phi", "nwe", "kan", "phi", "kan", "nwe"]'::jsonb,
  'and it carries the recap of which real season each pick came from'
);
select is(
  (select jsonb_path_query_array(qb_season_builder.result((select v from tests.fx where k = 'hid')), '$.picks[*].grade')),
  '["A-", "B+", "B+", "B+", "B-", "B-"]'::jsonb,
  'with each grade, a hidden run''s included now that it is finished'
);
select throws_ok(
  format($$ select qb_season_builder.result(%L) $$, (select v from tests.fx where k = 'notyet')),
  'P0002', 'result_not_found',
  'a run that is not finished has no result to read'
);
select tests.act_as_admin();

select tests.act_as_admin();
create temp table saved (k text primary key, j jsonb);
grant select on saved to public;
insert into saved (k, j)
select 'r', result from qb_season_builder_private.season_results
 where match_id = (select v from tests.fx where k = 'r');

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is(
  (select qb_season_builder.result((select v from tests.fx where k = 'r'))),
  (select j from saved where k = 'r'),
  'and a signed-in stranger reads the result exactly as it was saved'
);
select tests.act_as_admin();

select is(
  (select array_agg(k order by k) from jsonb_object_keys(qb_season_builder.result((select v from tests.fx where k = 'r'))) k),
  array['awards', 'breakdown', 'match_id', 'mode', 'picks', 'playoffs', 'record', 'score', 'stat_line'],
  'a result holds the season and the recap and nothing else'
);
select is(
  (select array_agg(k order by k)
     from jsonb_object_keys(qb_season_builder.result((select v from tests.fx where k = 'r')) -> 'picks' -> 0) k),
  array['display_name', 'franchise_code', 'grade', 'headshot_url', 'player_id', 'round', 'season', 'slot'],
  'a pick in the recap says what was taken from whom, the grade it earned and their headshot, and nothing else'
);
select ok(
  (select qb_season_builder.result((select v from tests.fx where k = 'r'))::text !~* '(seed|madden|source)'),
  'so no seed and no source rating is anywhere in it'
);

-- ------------------------------------------------------------------- the seed --

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok('select count(*) from qb_season_builder_private.season_results', '42501', null,
  'a signed-in player cannot read the saved results, where the seed is kept');
select throws_ok(
  format($$ select qb_season_builder_private.finish_run(%L, 1) $$, (select v from tests.fx where k = 'notyet')),
  '42501', null,
  'nor finish a run from a seed of their own');
select throws_ok(
  format($$ select qb_season_builder.finish(%L, 1) $$, (select v from tests.fx where k = 'notyet')),
  '42883', null,
  'the game''s finish takes no seed');
select ok(
  (select b::text !~* 'seed' from qb_season_builder.state((select v from tests.fx where k = 'hid')) b),
  'and the board of a finished run carries none');

set local role anon;
select throws_ok('select count(*) from qb_season_builder_private.season_results', '42501', null,
  'a signed-out client cannot read the seed either');
select tests.act_as_admin();

-- The Madden source ratings and the season model are as unreachable as the seed.
select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok('select count(*) from qb_season_builder_private.madden_ratings', '42501', null,
  'a signed-in player cannot read the source ratings');
select throws_ok('select count(*) from qb_season_builder_private.season_model_outputs', '42501', null,
  'nor the season model');
set local role anon;
select throws_ok('select count(*) from qb_season_builder_private.madden_ratings', '42501', null,
  'a signed-out client cannot read the source ratings');
select tests.act_as_admin();

-- ------------------------------------------------------------ personal bests --

select tests.qsb_model_fixtures();
insert into tests.fx (k, v) values ('pb', tests.mkuser('pat'));

-- Nothing yet, and a run merely in play does not make one.
select tests.act_as((select v from tests.fx where k = 'pb'));
insert into tests.fx (k, v)
select 'pbplay', tests.qsb_start((select v from tests.fx where k = 'pb'));
select tests.qsb_fill((select v from tests.fx where k = 'pbplay'), 5);
select is(
  (select count(*)::int from public.qb_season_builder_player_stats),
  0,
  'a player with no finished run has no personal best, and a run in play does not make one'
);

-- A visible run worth 72, then a hidden run worth 56 (every real season shifted
-- up one on each component).
select tests.act_as_admin();
select tests.qsb_finish_with_seed((select v from tests.fx where k = 'pb'), 1);
update qb_season_builder_private.season_model_distributions set value = value + 1;
select tests.qsb_finish_with_seed((select v from tests.fx where k = 'pb'), 1, 'hidden');

select tests.act_as((select v from tests.fx where k = 'pb'));
select is(
  (select best_score from public.qb_season_builder_player_stats where mode = 'visible'),
  72.0,
  'finishing a visible run sets the visible personal best'
);
select is(
  (select best_score from public.qb_season_builder_player_stats where mode = 'hidden'),
  56.0,
  'and finishing a hidden one sets the hidden best, separately'
);

-- A worse visible run (56 again) leaves the best where it was.
select tests.act_as_admin();
select tests.qsb_finish_with_seed((select v from tests.fx where k = 'pb'), 2);
select tests.act_as((select v from tests.fx where k = 'pb'));
select is(
  (select best_score from public.qb_season_builder_player_stats where mode = 'visible'),
  72.0,
  'a worse run does not lower it'
);

-- A better one (every real season shifted far below) raises the visible best only.
select tests.act_as_admin();
update qb_season_builder_private.season_model_distributions set value = value - 100;
select tests.qsb_finish_with_seed((select v from tests.fx where k = 'pb'), 3);
select tests.act_as((select v from tests.fx where k = 'pb'));
select is(
  (select best_score from public.qb_season_builder_player_stats where mode = 'visible'),
  100.0,
  'a better one raises it'
);
select is(
  (select best_score from public.qb_season_builder_player_stats where mode = 'hidden'),
  56.0,
  'without touching the other mode''s'
);
select is(
  (select count(*)::int from public.qb_season_builder_player_stats),
  2,
  'one best per mode, however many runs'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is(
  (select count(*)::int from public.qb_season_builder_player_stats),
  0,
  'another player cannot read it'
);

-- A guest plays, finishes and shares, and cannot read a personal best.
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'gb', tests.qsb_start((select v from tests.fx where k = 'guest'), 'visible', true);
select tests.qsb_fill((select v from tests.fx where k = 'gb'), 6);
select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'gb')),
  '42501', 'not_a_participant',
  'a guest''s run is theirs alone: nobody else can finish it');
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select lives_ok(
  format($$ select qb_season_builder.finish(%L) $$, (select v from tests.fx where k = 'gb')),
  'a guest can finish a run');
select is(
  (select count(*)::int from public.qb_season_builder_player_stats),
  0,
  'but cannot read a personal best'
);
select tests.act_as_admin();

set local role anon;
select is(
  (select count(*)::int from public.qb_season_builder_player_stats),
  0,
  'and neither can a signed-out client'
);
select tests.act_as_admin();

select * from finish();
rollback;
