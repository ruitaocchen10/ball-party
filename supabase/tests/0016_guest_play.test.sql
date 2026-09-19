begin;
select plan(10);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('guest', tests.mkguest('Devin'));

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select is(
  (select display_name from public.profiles where id = (select v from tests.fx where k = 'guest')),
  'Devin',
  'a guest receives the display name supplied at anonymous sign-in'
);

select is(
  (select is_guest from public.profiles where id = (select v from tests.fx where k = 'guest')),
  true,
  'a guest profile is marked for the room roster'
);

select throws_ok(
  format($$ update public.profiles set is_guest = false where id = %L $$, (select v from tests.fx where k = 'guest')),
  '42501', null,
  'a guest cannot forge the roster marker'
);

select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'lobby', (public.create_lobby()).id;

-- Multiplayer now requires a real account end to end (issue #61 / 0113): a
-- guest can no longer join a room, so the old "guest plays out a full
-- auction match" scenario this file used to cover is not a reachable path
-- through the API any more. 0113 owns the exhaustive multiplayer-entry-point
-- coverage; what's left here is guest identity itself, and the two entry
-- points closest to it.
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok(
  format($$ select public.join_lobby(%L) $$, tests.lobby_code((select v from tests.fx where k = 'lobby'))),
  '42501', 'account_required',
  'a guest cannot join a room'
);

select throws_ok(
  'select public.create_lobby()', '42501', 'not_authenticated',
  'a guest cannot create a room'
);

select tests.act_as_admin();
update public.lobbies set host_id = (select v from tests.fx where k = 'guest')
 where id = (select v from tests.fx where k = 'lobby');
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'account_required',
  'the retained run-start guard still rejects a guest'
);

select tests.act_as_admin();
update public.lobbies set host_id = (select v from tests.fx where k = 'host')
 where id = (select v from tests.fx where k = 'lobby');

-- Cleanup's run-participation guard (below) needs a guest who has actually
-- played, but that can no longer come from a real run: seat one directly, the
-- way an already-seated guest from before this migration would still look.
with new_run as (
  insert into public.runs (lobby_id, mode)
  values ((select v from tests.fx where k = 'lobby'), 'arcade')
  returning id
)
insert into tests.fx (k, v) select 'run', id from new_run;
insert into public.run_participants (run_id, user_id, seat)
values ((select v from tests.fx where k = 'run'), (select v from tests.fx where k = 'guest'), 0);

-- The collision is asserted in two halves, each proven by auth.uid(): the
-- guest stakes a claim on itself, the account redeems the nonce. See 0017.
insert into tests.fx (k, v) values ('account', tests.mkuser('Morgan'));
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
insert into tests.fx (k, v) select 'nonce', public.claim_guest_identity();

select tests.act_as((select v from tests.fx where k = 'account'));
select lives_ok(
  format($$ select public.record_guest_account_collision(%L) $$, (select v from tests.fx where k = 'nonce')),
  'signing into a separate account records the guest identity'
);
select tests.act_as_admin();
select is(
  (select account_id from public.guest_account_collisions where guest_id = (select v from tests.fx where k = 'guest')),
  (select v from tests.fx where k = 'account'),
  'the collision breadcrumb keeps both identities'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('empty', tests.mkguest('Empty'));
update auth.users set created_at = now() - interval '31 days' where id = (select v from tests.fx where k = 'empty');
select private.cleanup_guest_accounts();
select is((select count(*)::int from auth.users where id = (select v from tests.fx where k = 'empty')), 0,
  'the cleanup removes an unplayed guest after thirty days');

select is((select count(*)::int from auth.users where id = (select v from tests.fx where k = 'guest')), 1,
  'the cleanup cannot delete a guest with run participation');

select * from finish();
rollback;
