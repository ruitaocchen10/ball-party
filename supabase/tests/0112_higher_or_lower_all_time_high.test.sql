begin;
select plan(3);
\ir support/harness.psql

insert into tests.fx (k, v) values ('ava', tests.mkuser('ava'));
insert into tests.fx (k, v)
select 'solo', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'ava'), 0.3);
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'solo');

-- A settled correct solo answer grows both the match streak and the durable
-- profile record. `call` reveals immediately for a one-player board.
select tests.open_question((select v from tests.fx where k = 'solo'), 1::smallint);
select tests.act_as((select v from tests.fx where k = 'ava'));
select higher_or_lower.call((select v from tests.fx where k = 'solo'),
  tests.hol_answer((select v from tests.fx where k = 'solo'), 1::smallint));
select tests.act_as_admin();
select is((select all_time_high from public.higher_or_lower_player_stats
  where user_id = (select v from tests.fx where k = 'ava')),
  1, 'a correct solo answer creates the durable all-time high');

update public.higher_or_lower_players set best_streak = 4
 where match_id = (select v from tests.fx where k = 'solo');
select is((select all_time_high from public.higher_or_lower_player_stats
  where user_id = (select v from tests.fx where k = 'ava')),
  4, 'a higher solo best streak raises the durable record');

update public.higher_or_lower_players set best_streak = 2
 where match_id = (select v from tests.fx where k = 'solo');
select is((select all_time_high from public.higher_or_lower_player_stats
  where user_id = (select v from tests.fx where k = 'ava')),
  4, 'a lower later streak cannot reduce the durable record');

select * from finish();
rollback;
