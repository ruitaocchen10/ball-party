-- The post-game choice is a host-authorized room transition. These assertions
-- observe its durable result, rather than its private dealer calls.
begin;
select plan(10);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('player', tests.mkuser('Devin'));

insert into tests.fx (k, v)
values ('lobby', tests.mklobby(array[
  (select v from tests.fx where k = 'host'),
  (select v from tests.fx where k = 'player')
]));

select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'match', (public.start_run((select v from tests.fx where k = 'lobby'), 'arcade', 'auction_team_builder')).id;

select tests.act_as_admin();
select auction_private.deal_board((select v from tests.fx where k = 'match'), .25, 'season_total', 'full');
update public.matches set status = 'playing' where id = (select v from tests.fx where k = 'match');
select private.finish_match(
  (select v from tests.fx where k = 'match'),
  (select jsonb_object_agg(user_id::text, 1) from public.run_participants
    where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'match')))
);

-- A player can see the completed match but cannot move everyone on from it.
select tests.act_as((select v from tests.fx where k = 'player'));
select throws_ok(
  format($$ select public.choose_post_game(%L, 'replay'::public.post_game_choice) $$, (select v from tests.fx where k = 'match')),
  '42501', 'not_host',
  'a player cannot choose the room’s post-game destination'
);

select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'replay', next_match_id from public.choose_post_game((select v from tests.fx where k = 'match'), 'replay'::public.post_game_choice);

select is(
  (select choice::text from public.post_game_actions where match_id = (select v from tests.fx where k = 'match')),
  'replay', 'the host’s replay choice is durable'
);
select isnt((select v from tests.fx where k = 'replay'), null::uuid, 'replay names the new match');
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'replay')),
  'playing', 'replay starts a fresh live match'
);
select is(
  (select mode::text from public.runs r join public.matches m on m.run_id = r.id where m.id = (select v from tests.fx where k = 'replay')),
  'arcade', 'replay starts an arcade run'
);
select set_eq(
  $$ select user_id from public.run_participants where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'match')) $$,
  $$ select user_id from public.run_participants where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'replay')) $$,
  'replay keeps the completed game’s roster'
);
select is(
  (select scoring_mode from public.auction_matches where match_id = (select v from tests.fx where k = 'replay')),
  'season_total', 'replay keeps the scoring mode'
);
select is(
  (select roster_preset from public.auction_matches where match_id = (select v from tests.fx where k = 'replay')),
  'full', 'replay keeps the roster preset'
);

select tests.act_as((select v from tests.fx where k = 'player'));
select is(
  (select choice::text from public.post_game_actions where match_id = (select v from tests.fx where k = 'match')),
  'replay', 'a room player can read the transition that moves their tab'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select throws_ok(
  format($$ select public.choose_post_game(%L, 'lobby'::public.post_game_choice) $$, (select v from tests.fx where k = 'match')),
  'P0001', 'post_game_choice_already_made',
  'the completed match has one authoritative next destination'
);

select * from finish();
rollback;
