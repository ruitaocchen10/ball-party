-- Tests for 0214: the Rams are LAR everywhere. The validator takes LAR and not
-- LA, and both nflverse importers convert LA on the way in while leaving the
-- game id (nflverse's own key) alone.

begin;
select plan(8);
\ir support/harness.psql

select ok(prompts_private.is_valid_team_code('LAR'), 'LAR is a valid team code');
select ok(not prompts_private.is_valid_team_code('LA'), 'LA is not');
select ok(prompts_private.is_valid_team_code('LAC'), 'the Chargers are still LAC');

-- ------------------------------------------------------------ the schedule --

delete from public.nfl_games;
select prompts_private.sync_nfl_games(
  E'game_id,season,game_type,week,gameday,gametime,away_team,home_team,stadium\n'
  || E'2026_05_BUF_LA,2026,REG,5,2026-10-11,13:00,BUF,LA,SoFi Stadium\n'
  || E'2026_06_LA_SF,2026,REG,6,2026-10-18,13:00,LA,SF,Levi''s Stadium\n'
  || E'2026_07_LAC_KC,2026,REG,7,2026-10-25,13:00,LAC,KC,Arrowhead Stadium\n');

select is((select home_team from public.nfl_games where id = '2026_05_BUF_LA'), 'LAR', 'a home LA is stored as LAR, under nflverse''s own game id');
select is((select away_team from public.nfl_games where id = '2026_06_LA_SF'), 'LAR', 'an away LA is stored as LAR');
select is((select away_team from public.nfl_games where id = '2026_07_LAC_KC'), 'LAC', 'the Chargers are untouched');

-- ---------------------------------------------------------- the directory --

select prompts_private.sync_nfl_players(
  E'season,team,position,status,full_name,gsis_id,headshot_url\n'
  || E'2026,LA,WR,ACT,Pat Receiver,00-9990001,\n'
  || E'2026,LAC,WR,ACT,Sam Receiver,00-9990002,\n');

select is((select team from prompts_private.nfl_players where player_id = '00-9990001'), 'LAR', 'a Rams player from the roster file is on LAR');
select is((select team from prompts_private.nfl_players where player_id = '00-9990002'), 'LAC', 'a Chargers player stays on LAC');

select * from finish();
rollback;
