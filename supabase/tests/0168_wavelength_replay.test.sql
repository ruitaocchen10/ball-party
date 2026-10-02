-- Replaying a finished Wavelength match keeps its mode and preset, and the
-- host alone chooses it (choose_post_game, redefined in 0168).

begin;
select plan(7);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.mkmatch(2, 'wavelength_2v2'));
select tests.act_as_admin();
select wavelength_private.deal_board((select v from tests.fx where k = 'm'), 'coop', 'medium', 0.25);
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm');
select private.finish_match(
  (select v from tests.fx where k = 'm'),
  (select jsonb_object_agg(user_id::text, 1) from public.run_participants
    where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm')))
);

insert into tests.fx (k, v) select 'host', host_id from public.lobbies
 where id = (select lobby_id from public.runs where id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm')));
insert into tests.fx (k, v) select 'guest', user_id from public.run_participants
 where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm'))
   and user_id <> (select v from tests.fx where k = 'host');

select tests.act_as((select v from tests.fx where k = 'guest'));
select throws_ok(
  format($$ select public.choose_post_game(%L, 'replay'::public.post_game_choice) $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_host', 'a player cannot choose the replay'
);

select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'next', next_match_id from public.choose_post_game((select v from tests.fx where k = 'm'), 'replay'::public.post_game_choice);

select tests.act_as_admin();
select is((select status::text from public.matches where id = (select v from tests.fx where k = 'next')), 'playing', 'replay starts a live match');
select is((select game::text from public.matches where id = (select v from tests.fx where k = 'next')), 'wavelength_2v2', 'replay stays Wavelength');
select is((select mode || '/' || preset from public.wavelength_matches where match_id = (select v from tests.fx where k = 'next')), 'coop/medium', 'replay keeps the mode and preset');
select is((select phase from public.wavelength_matches where match_id = (select v from tests.fx where k = 'next')), 'fill', 'replay opens in the fill phase');
select is((select count(*)::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'next')), 6, 'replay deals a fresh board');
select set_eq(
  $$ select user_id from public.wavelength_players where match_id = (select v from tests.fx where k = 'next') $$,
  $$ select user_id from public.run_participants where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm')) $$,
  'the same players carry over'
);

select * from finish();
rollback;
