-- Room codes are long link tokens (migration 0198): a new room gets 16
-- characters from the unambiguous alphabet, and joining by that code still
-- works. A five-character code from a room opened before the change is still
-- a valid code.

begin;
select plan(4);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('friend', tests.mkuser('Ben'));

select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'lobby', (public.create_lobby()).id;

select is(
  length(tests.lobby_code((select v from tests.fx where k = 'lobby'))),
  16,
  'a new room gets a 16-character code'
);

select matches(
  tests.lobby_code((select v from tests.fx where k = 'lobby')),
  '^[2-9A-HJKMNP-Z]{16}$',
  'the code uses the mishear-proof alphabet'
);

select tests.act_as((select v from tests.fx where k = 'friend'));
select lives_ok(
  format($$ select public.join_lobby(%L) $$, tests.lobby_code((select v from tests.fx where k = 'lobby'))),
  'a player can join with the long code'
);

select tests.act_as_admin();
select lives_ok(
  format($$ update public.lobbies set code = 'AB234' where id = %L $$, (select v from tests.fx where k = 'lobby')),
  'a five-character code from an older room is still valid'
);

select * from finish();
rollback;
