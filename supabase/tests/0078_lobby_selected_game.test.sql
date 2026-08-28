-- The room's own "next up" pick: host-only, readable by any current member.
begin;
select plan(8);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('member', tests.mkuser('Bo')),
       ('stranger', tests.mkuser('Cy'));

insert into tests.fx (k, v)
values ('lobby', tests.mklobby(array[
  (select v from tests.fx where k = 'host'),
  (select v from tests.fx where k = 'member')
]));

select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(
  format($$ select public.select_lobby_game(%L, 'sabotage_draft') $$, (select v from tests.fx where k = 'lobby')),
  'the host can select a game'
);

select tests.act_as_admin();
select is(
  (select selected_game from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  'sabotage_draft',
  'the selection is recorded on the room'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(
  format($$ select public.select_lobby_game(%L, 'higher_or_lower') $$, (select v from tests.fx where k = 'lobby')),
  'the host can change the selection'
);

select tests.act_as_admin();
select is(
  (select selected_game from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  'higher_or_lower',
  'a later selection overwrites the earlier one'
);

select tests.act_as((select v from tests.fx where k = 'member'));
select throws_ok(
  format($$ select public.select_lobby_game(%L, 'sabotage_draft') $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'not_host',
  'a non-host member cannot change the selection'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select public.select_lobby_game(%L, 'sabotage_draft') $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'not_host',
  'someone outside the room cannot change the selection either'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select throws_ok(
  $$ select public.select_lobby_game('00000000-0000-0000-0000-000000000000', 'sabotage_draft') $$,
  'P0001', 'lobby_not_found',
  'a room that does not exist refuses the selection'
);

select throws_ok(
  format($$ select public.select_lobby_game(%L, 'not_a_real_game') $$, (select v from tests.fx where k = 'lobby')),
  '23514', 'new row for relation "lobbies" violates check constraint "lobbies_selected_game_check"',
  'an unrecognised game name is rejected by the check constraint'
);

select * from finish();
rollback;
