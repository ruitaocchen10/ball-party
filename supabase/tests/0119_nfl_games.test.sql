-- Tests for the shared NFL schedule (0119): the CSV row parser, sync_nfl_games's
-- parsing/conversion/upsert against a fabricated nflverse file, and who may read
-- or write public.nfl_games. Like 0096's suite, this deliberately does NOT run
-- auto_resolve_tick, whose net.http_get would make the suite depend on the
-- network; sync_nfl_games takes CSV text so its logic is testable without it.

begin;
select plan(28);
\ir support/harness.psql

-- ------------------------------------------------------------- csv_fields --

select is(prompts_private.csv_fields('a,b,c'), array['a','b','c'], 'a plain row splits on commas');
select is(prompts_private.csv_fields('a,"b,c",d'), array['a','b,c','d'], 'a quoted value keeps its comma');
select is(prompts_private.csv_fields('a,"",c'), array['a','','c'], 'a quoted empty value ("") is an empty field, not a stray quote');
select is(prompts_private.csv_fields('a,"say ""hi""",c'), array['a','say "hi"','c'], 'a doubled quote inside quotes is one literal quote');
select is(prompts_private.csv_fields('a,b,'), array['a','b',''], 'a trailing comma leaves a trailing empty field');
select is(prompts_private.csv_fields(E'a,b\r'), array['a','b'], 'a CRLF line ending does not leak into the last field');

-- -------------------------------------------------------- sync_nfl_games --

-- A dev database that has run the poll already holds the real schedule, which
-- would make every count below depend on it. This transaction rolls back, so
-- emptying the table here costs nothing.
delete from public.nfl_games;

-- The columns are deliberately reordered and padded relative to the real file,
-- so this also proves fields are found by header name and not by position.
--   1  Sun 13:00 EDT  → 17:00Z, not primetime
--   2  Sun 20:20 EST  → 01:20Z the next day (a December kickoff, after the
--                       clocks change), primetime
--   3  Mon 20:15      → primetime
--   4  Thu 20:15      → primetime
--   5  Sat 20:00      → not primetime: Saturday is no national window
--   6  Sun 09:30      → not primetime: a London morning game
--   7  a stadium whose name holds a comma
-- and four rows that must not appear: a playoff game, a game with no time yet,
-- a game with a non-numeric week, and a game with no teams.
create function tests.fake_games() returns text
language sql as $$
  select string_agg(line, E'\n') from (values
    ('stadium,game_id,padding,season,game_type,week,gameday,gametime,away_team,home_team'),
    ('Field One,2026_01_AAA_BBB,x,2026,REG,1,2026-09-13,13:00,AAA,BBB'),
    ('Field Two,2026_14_CCC_DDD,x,2026,REG,14,2026-12-06,20:20,CCC,DDD'),
    ('Field Three,2026_14_EEE_FFF,x,2026,REG,14,2026-12-07,20:15,EEE,FFF'),
    ('Field Four,2026_02_GGG_HHH,x,2026,REG,2,2026-09-17,20:15,GGG,HHH'),
    ('Field Five,2026_16_III_JJJ,x,2026,REG,16,2026-12-19,20:00,III,JJJ'),
    ('Wembley,2026_05_KKK_LLL,x,2026,REG,5,2026-10-11,09:30,KKK,LLL'),
    ('"Arrowhead, Kansas City",2026_03_MMM_NNN,x,2026,REG,3,2026-09-20,13:00,MMM,NNN'),
    ('Field Post,2026_20_OOO_PPP,x,2026,POST,20,2027-01-17,15:00,OOO,PPP'),
    ('Field Tbd,2026_18_QQQ_RRR,x,2026,REG,18,2027-01-03,,QQQ,RRR'),
    ('Field Week,2026_xx_SSS_TTT,x,2026,REG,xx,2026-09-13,13:00,SSS,TTT'),
    ('Field Teams,2026_04_UUU_VVV,x,2026,REG,4,2026-09-27,13:00,,')
  ) as t(line)
$$;

select is(prompts_private.sync_nfl_games(tests.fake_games()), 7, 'seven valid regular-season games are inserted; playoff, timeless, bad-week and teamless rows are skipped');
select is((select count(*)::int from public.nfl_games), 7, 'and nothing else landed in the table');

select is((select kickoff from public.nfl_games where id = '2026_01_AAA_BBB'),
  '2026-09-13 17:00:00+00'::timestamptz, 'a September kickoff converts Eastern to UTC across daylight time (UTC-4)');
select is((select kickoff from public.nfl_games where id = '2026_14_CCC_DDD'),
  '2026-12-07 01:20:00+00'::timestamptz, 'a December kickoff converts across standard time (UTC-5), rolling into the next UTC day');

select is((select primetime from public.nfl_games where id = '2026_01_AAA_BBB'), false, 'a Sunday 1pm game is not primetime');
select is((select primetime from public.nfl_games where id = '2026_14_CCC_DDD'), true, 'Sunday night is primetime');
select is((select primetime from public.nfl_games where id = '2026_14_EEE_FFF'), true, 'Monday night is primetime');
select is((select primetime from public.nfl_games where id = '2026_02_GGG_HHH'), true, 'Thursday night is primetime');
select is((select primetime from public.nfl_games where id = '2026_16_III_JJJ'), false, 'a Saturday night game is not primetime');
select is((select primetime from public.nfl_games where id = '2026_05_KKK_LLL'), false, 'a Sunday 9:30am game is not primetime');

select is((select stadium from public.nfl_games where id = '2026_03_MMM_NNN'), 'Arrowhead, Kansas City', 'a quoted stadium name keeps its comma');
select is((select array[away_team, home_team, season::text, week::text] from public.nfl_games where id = '2026_03_MMM_NNN'),
  array['MMM','NNN','2026','3'], 'teams, season and week are read by header name from a reordered file');

-- Running the same file again is the ordinary case: the poll refreshes hourly.
select is(prompts_private.sync_nfl_games(tests.fake_games()), 0, 'syncing an unchanged schedule changes nothing');

-- A flexed game: same id, new kickoff.
update public.nfl_games set updated_at = '2000-01-01' where id = '2026_14_CCC_DDD';
select is(
  prompts_private.sync_nfl_games(replace(tests.fake_games(), '2026-12-06,20:20,CCC', '2026-12-06,16:25,CCC')),
  1, 'a moved kickoff updates exactly that game');
select is((select kickoff from public.nfl_games where id = '2026_14_CCC_DDD'),
  '2026-12-06 21:25:00+00'::timestamptz, 'the game now has its new kickoff');
select is((select primetime from public.nfl_games where id = '2026_14_CCC_DDD'), false, 'and is no longer primetime');
select cmp_ok((select updated_at from public.nfl_games where id = '2026_14_CCC_DDD'), '>', '2000-01-01'::timestamptz,
  'and its updated_at moves');

-- A feed that loses a column must fail loudly rather than write nothing (or
-- nulls) and look healthy.
select throws_ok(
  $$ select prompts_private.sync_nfl_games(E'game_id,season,game_type,week,gameday,away_team,home_team,stadium\n2026_01_A_B,2026,REG,1,2026-09-13,A,B,S') $$,
  'P0001', 'nflverse schedule is missing the gametime column', 'a header without a required column raises');

-- ------------------------------------------------------------ who can read --

insert into tests.fx (k, v) values ('reader', tests.mkuser('reader'));

select set_config('role', 'anon', true);
select is((select count(*)::int from public.nfl_games), 7, 'a signed-out visitor can read the schedule');
select throws_ok($$ insert into public.nfl_games (id, season, week, kickoff, away_team, home_team) values ('x', 2026, 1, now(), 'A', 'B') $$,
  '42501', null, 'and cannot insert into it');

-- Back to the owner before calling a tests.* helper, which anon can't reach.
select set_config('role', 'postgres', true);
select tests.act_as((select v from tests.fx where k = 'reader'));
select throws_ok($$ update public.nfl_games set stadium = 'hacked' $$, '42501', null, 'a signed-in player cannot update it');
select throws_ok($$ select prompts_private.sync_nfl_games('x') $$, '42501', null,
  'and cannot reach sync_nfl_games: prompts_private is closed to client roles');

select * from finish();
rollback;
