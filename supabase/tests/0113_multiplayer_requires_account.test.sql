-- Multiplayer requires a real account (issue #61, companion to the iOS spec
-- in #59). iOS never carries a guest session at all, so the two clients only
-- agree if the web's multiplayer entry points refuse one too. Solo is the
-- control: guest play is not going away, only its multiplayer half.
--
-- `account_required` is the guest-specific rejection, distinct from
-- `not_authenticated` (no session at all) — a guest already has a working
-- session, so telling them to sign in again would be the confusing error the
-- product spec calls out.

begin;
select plan(9);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('guest', tests.mkguest('Devin'));

select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'lobby', (public.create_lobby()).id;

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok(
  format($$ select public.join_lobby(%L) $$, tests.lobby_code((select v from tests.fx where k = 'lobby'))),
  '42501', 'account_required',
  'a guest cannot join a room'
);

select throws_ok(
  format($$ select public.select_lobby_game(%L, 'higher_or_lower') $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'account_required',
  'a guest cannot choose the room''s next game'
);

select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'higher_or_lower') $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'account_required',
  'a guest cannot start a run'
);

select lives_ok(
  'select public.start_solo_run(''higher_or_lower'')',
  'solo play remains guest-accessible'
);

-- The same three calls, made by the account that actually holds the room,
-- still work — the migration narrows who may act, not what a real account
-- may do.
insert into tests.fx (k, v) values ('friend', tests.mkuser('Bo'));
select tests.act_as((select v from tests.fx where k = 'friend'));
select lives_ok(
  format($$ select public.join_lobby(%L) $$, tests.lobby_code((select v from tests.fx where k = 'lobby'))),
  'a signed-in, non-guest account can still join a room'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(
  format($$ select public.select_lobby_game(%L, 'higher_or_lower') $$, (select v from tests.fx where k = 'lobby')),
  'the host can still choose the room''s next game'
);

select lives_ok(
  format($$ select public.start_run(%L, 'arcade', 'higher_or_lower') $$, (select v from tests.fx where k = 'lobby')),
  'the host can still start a run'
);

select is(
  (select count(*)::int from public.run_participants rp
    join public.runs r on r.id = rp.run_id
   where r.lobby_id = (select v from tests.fx where k = 'lobby')),
  2,
  'the started run seats only the room''s two real accounts'
);

-- A guest seated from before this migration shipped isn't retroactively
-- removed from lobby_members. start_run seats every current member, not
-- just its caller, so without this check a real host could still carry that
-- grandfathered guest into a match.
insert into tests.fx (k, v) values ('host2', tests.mkuser('Cam')), ('legacy_guest', tests.mkguest('Sam'));
select tests.act_as((select v from tests.fx where k = 'host2'));
insert into tests.fx (k, v)
select 'lobby2', (public.create_lobby()).id;

select tests.act_as_admin();
insert into public.lobby_members (lobby_id, user_id)
values ((select v from tests.fx where k = 'lobby2'), (select v from tests.fx where k = 'legacy_guest'));

select tests.act_as((select v from tests.fx where k = 'host2'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'higher_or_lower') $$, (select v from tests.fx where k = 'lobby2')),
  '42501', 'account_required',
  'a real host cannot start a run that would seat a grandfathered guest member'
);

select * from finish();
rollback;
