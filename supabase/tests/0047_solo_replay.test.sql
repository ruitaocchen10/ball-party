-- Solo replay (issue #34) is the same durable post-game decision as a room
-- replay, but its authority and next-run shape belong to the sole player.

begin;
select plan(7);

\ir support/harness.psql

insert into tests.fx (k, v) values ('player', tests.mkuser('ava'));

insert into tests.fx (k, v)
select 'match', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'player'), 0.3);

select tests.act_as_admin();
select private.finish_match(
  (select v from tests.fx where k = 'match'),
  jsonb_build_object((select v from tests.fx where k = 'player')::text, 9)
);

select tests.act_as((select v from tests.fx where k = 'player'));
insert into tests.fx (k, v)
select 'replay', next_match_id from public.choose_post_game(
  (select v from tests.fx where k = 'match'), 'replay'::public.post_game_choice
);

select isnt((select v from tests.fx where k = 'replay'), null::uuid, 'solo replay names a new match');
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'replay')),
  'playing', 'solo replay starts a live match'
);
select is(
  (select mode::text from public.runs r join public.matches m on m.run_id = r.id
    where m.id = (select v from tests.fx where k = 'replay')),
  'solo', 'solo replay creates another solo run'
);
select is(
  (select lobby_id from public.runs r join public.matches m on m.run_id = r.id
    where m.id = (select v from tests.fx where k = 'replay')),
  null, 'solo replay carries no lobby'
);
select is(
  (select user_id from public.run_participants rp join public.matches m on m.run_id = rp.run_id
    where m.id = (select v from tests.fx where k = 'replay')),
  (select v from tests.fx where k = 'player'), 'solo replay seats the original player'
);
select is(
  (select row(scoring_mode, season_from, season_to)::text from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'replay')),
  (select row(scoring_mode, season_from, season_to)::text from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'match')),
  'solo replay keeps the completed match format'
);
select throws_ok(
  format($$ select public.choose_post_game(%L, 'replay'::public.post_game_choice) $$,
         (select v from tests.fx where k = 'match')),
  'P0001', 'post_game_choice_already_made',
  'a completed solo match has one authoritative next destination'
);

select * from finish();
rollback;
