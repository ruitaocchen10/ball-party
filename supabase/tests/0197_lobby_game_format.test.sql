-- The room's saved game settings: host-only to write, readable by members.
begin;
select plan(9);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('member', tests.mkuser('Bo')),
       ('stranger', tests.mkuser('Cy'));

insert into tests.fx (k, v)
values ('lobby', tests.mklobby(array[
  (select v from tests.fx where k = 'host'),
  (select v from tests.fx where k = 'member')
]));

select tests.act_as_admin();
select is(
  (select game_format from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  '{}'::jsonb,
  'a new room has no saved settings'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(
  format($$ select public.set_lobby_game_format(%L, '{"higher_or_lower": {"scoring_mode": "weekly"}}'::jsonb) $$,
         (select v from tests.fx where k = 'lobby')),
  'the host can save settings'
);

select tests.act_as((select v from tests.fx where k = 'member'));
select is(
  (select game_format from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  '{"higher_or_lower": {"scoring_mode": "weekly"}}'::jsonb,
  'another member can read them'
);

select throws_ok(
  format($$ select public.set_lobby_game_format(%L, '{}'::jsonb) $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'not_host',
  'a non-host member cannot change them'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select public.set_lobby_game_format(%L, '{}'::jsonb) $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'not_host',
  'someone outside the room cannot change them either'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(
  format($$ select public.set_lobby_game_format(%L, '{"wavelength_2v2": {"mode": "coop"}}'::jsonb) $$,
         (select v from tests.fx where k = 'lobby')),
  'saving replaces the whole blob'
);
select tests.act_as_admin();
select is(
  (select game_format from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  '{"wavelength_2v2": {"mode": "coop"}}'::jsonb,
  'the earlier settings are gone, not merged'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select throws_ok(
  format($$ select public.set_lobby_game_format(%L, '[1,2]'::jsonb) $$, (select v from tests.fx where k = 'lobby')),
  '23514', 'new row for relation "lobbies" violates check constraint "lobbies_game_format_object"',
  'settings must be an object'
);
select throws_ok(
  format($$ select public.set_lobby_game_format(%L, jsonb_build_object('x', repeat('a', 5000))) $$,
         (select v from tests.fx where k = 'lobby')),
  '23514', 'new row for relation "lobbies" violates check constraint "lobbies_game_format_size"',
  'settings are capped in size'
);

select * from finish();
rollback;
