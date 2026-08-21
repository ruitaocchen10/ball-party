-- Tests for solo play, platform side (migration 0044). See issue #32.
--
-- Three things: start_solo_run builds the run/participant/match shape a solo
-- match needs with no lobby anywhere in it; the RLS rewrite lets the solo
-- player read their own four rows and nobody else's; and the lobby-backed
-- path those policies also gate is unaffected.

begin;
select plan(26);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina')),
       ('stranger', tests.mkuser('sten'));

-- --------------------------------------------------------------- the shape --

select tests.act_as((select v from tests.fx where k = 'a'));
insert into tests.fx (k, v)
select 'match', (public.start_solo_run('higher_or_lower')).id;

select tests.act_as_admin();

insert into tests.fx (k, v)
select 'run', run_id from public.matches where id = (select v from tests.fx where k = 'match');

select is(
  (select mode::text from public.runs where id = (select v from tests.fx where k = 'run')),
  'solo', 'a solo run is tagged solo'
);
select is(
  (select lobby_id from public.runs where id = (select v from tests.fx where k = 'run')),
  null, 'a solo run carries no lobby'
);
select is(
  (select status::text from public.runs where id = (select v from tests.fx where k = 'run')),
  'active', 'a solo run starts active, the same as any other'
);

select is(
  (select count(*)::int from public.run_participants
    where run_id = (select v from tests.fx where k = 'run')),
  1, 'starting a solo run seats exactly one participant'
);
select is(
  (select user_id from public.run_participants
    where run_id = (select v from tests.fx where k = 'run')),
  (select v from tests.fx where k = 'a'), 'the one seat is the caller'
);
select is(
  (select seat::int from public.run_participants
    where run_id = (select v from tests.fx where k = 'run')),
  0, 'seated at 0 — there is no rotation to randomise'
);

select is(
  (select game from public.matches where id = (select v from tests.fx where k = 'match')),
  'higher_or_lower', 'the match carries the game it was started for'
);
select is(
  (select seq::int from public.matches where id = (select v from tests.fx where k = 'match')),
  1, 'the match is seq 1'
);
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'match')),
  'setup', 'the match is created in setup, for the game to take over'
);

-- The constraint tying mode to lobby_id, exercised directly rather than only
-- through start_solo_run — a hand-built row is what would slip past a helper
-- function that forgot to check.
insert into tests.fx (k, v)
select 'lobby', tests.mklobby(array[tests.mkuser('lonely')]);

select tests.act_as_admin();
select throws_ok(
  format($$ insert into public.runs (lobby_id, mode) values (%L, 'solo') $$,
         (select v from tests.fx where k = 'lobby')),
  '23514', null,
  'a run cannot be solo while carrying a lobby'
);
select throws_ok(
  $$ insert into public.runs (lobby_id, mode) values (null, 'arcade') $$,
  '23514', null,
  'a lobby-backed mode cannot go without a lobby'
);

-- --------------------------------------------------------- guests can play --

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select lives_ok(
  $$ select public.start_solo_run('higher_or_lower') $$,
  'a guest session can start a solo run — the host boundary never applied here'
);

insert into tests.fx (k, v)
select 'guest_match', (public.start_solo_run('higher_or_lower')).id;

select tests.act_as_admin();
insert into tests.fx (k, v)
select 'guest_run', run_id from public.matches where id = (select v from tests.fx where k = 'guest_match');
select is(
  (select user_id from public.run_participants
    where run_id = (select v from tests.fx where k = 'guest_run')),
  (select v from tests.fx where k = 'guest'), 'the guest is seated in their own solo run'
);

-- ---------------------------------------------------------------------- RLS --

-- A row on match_players so the fourth table has something to allow or deny —
-- an empty result set from an allow-path query would look identical to a
-- denied one.
select private.finish_match(
  (select v from tests.fx where k = 'match'),
  jsonb_build_object((select v from tests.fx where k = 'a')::text, 9)
);

select tests.act_as((select v from tests.fx where k = 'a'));

select is(
  (select count(*)::int from public.runs where id = (select v from tests.fx where k = 'run')),
  1, 'the solo player can read their own run'
);
select is(
  (select count(*)::int from public.run_participants
    where run_id = (select v from tests.fx where k = 'run')),
  1, 'the solo player can read their own run_participants row'
);
select is(
  (select count(*)::int from public.matches where id = (select v from tests.fx where k = 'match')),
  1, 'the solo player can read their own match'
);
select is(
  (select count(*)::int from public.match_players where match_id = (select v from tests.fx where k = 'match')),
  1, 'the solo player can read their own match_players row'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));

select is_empty(
  format($$ select 1 from public.runs where id = %L $$, (select v from tests.fx where k = 'run')),
  'a different signed-in user cannot read someone else''s solo run'
);
select is_empty(
  format($$ select 1 from public.run_participants where run_id = %L $$, (select v from tests.fx where k = 'run')),
  'nor their run_participants row'
);
select is_empty(
  format($$ select 1 from public.matches where id = %L $$, (select v from tests.fx where k = 'match')),
  'nor their match'
);
select is_empty(
  format($$ select 1 from public.match_players where match_id = %L $$, (select v from tests.fx where k = 'match')),
  'nor their match_players row'
);

-- --------------------------------------------- group mode is unaffected --

-- The same four tables, lobby-backed this time, to prove the rewrite of
-- is_run_member / is_match_member / runs_select_member kept the existing path
-- working rather than only adding a new one beside it.
insert into tests.fx (k, v)
select 'group_match', tests.mkmatch(2, 'auction_team_builder');
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'group_run', run_id from public.matches where id = (select v from tests.fx where k = 'group_match');

select is(
  (select count(*)::int from public.lobby_members lm
     join public.runs r on r.lobby_id = lm.lobby_id
    where r.id = (select v from tests.fx where k = 'group_run')
      and lm.user_id = (select v from tests.fx where k = 'stranger')),
  0, 'sanity: the stranger really is outside this room'
);

insert into tests.fx (k, v)
select 'member', lm.user_id
  from public.lobby_members lm
  join public.runs r on r.lobby_id = lm.lobby_id
 where r.id = (select v from tests.fx where k = 'group_run')
 limit 1;

select tests.act_as((select v from tests.fx where k = 'member'));
select is(
  (select count(*)::int from public.runs where id = (select v from tests.fx where k = 'group_run')),
  1, 'a current lobby member still reads their room''s run'
);
select is(
  (select count(*)::int from public.matches where id = (select v from tests.fx where k = 'group_match')),
  1, 'and their room''s match'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is_empty(
  format($$ select 1 from public.runs where id = %L $$, (select v from tests.fx where k = 'group_run')),
  'a player who is not a current lobby member still cannot read another room''s run'
);
select is_empty(
  format($$ select 1 from public.matches where id = %L $$, (select v from tests.fx where k = 'group_match')),
  'nor its match'
);

select * from finish();
rollback;
