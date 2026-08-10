-- Tests for the runs-and-matches write API (migration 0009).
--
-- These assert on observable database state after calling the public function,
-- never on intermediate steps. Concurrency is asserted through the index rather
-- than through timing: racing two start_run calls from a test is unreliable, so
-- the durable version of the claim is that the partial unique index exists and
-- that the function maps its violation to run_already_active.

begin;
select plan(30);

\ir support/harness.psql

-- ----------------------------------------------------------- the happy path --

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')), ('b', tests.mkuser('bo')),
       ('c', tests.mkuser('cy')), ('d', tests.mkuser('di'));

insert into tests.fx (k, v)
values ('lobby', tests.mklobby(array[
  (select v from tests.fx where k = 'a'),
  (select v from tests.fx where k = 'b'),
  (select v from tests.fx where k = 'c'),
  (select v from tests.fx where k = 'd')
]));

-- A non-host member cannot start.
select tests.act_as((select v from tests.fx where k = 'b'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby')),
  '42501', 'not_host',
  'a member who is not the host cannot start a run'
);

-- A stranger cannot start either — they fail the host check first, which is
-- the honest answer: they are not the host of a room they are not in.
select tests.act_as(tests.mkuser('stranger'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby')),
  '42501', 'not_host',
  'someone outside the room cannot start a run in it'
);

-- Party is rejected while the enum still accepts the value.
select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  format($$ select public.start_run(%L, 'party', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby')),
  'P0001', 'mode_not_supported',
  'party is rejected even though run_mode still carries it'
);

-- The host starts.
insert into tests.fx (k, v)
select 'match', (public.start_run(
  (select v from tests.fx where k = 'lobby'), 'arcade', 'auction_team_builder')).id;

select tests.act_as_admin();

select is(
  (select count(*)::int from public.runs
    where lobby_id = (select v from tests.fx where k = 'lobby')),
  1,
  'starting a run produces exactly one run'
);

select is(
  (select status::text from public.runs
    where lobby_id = (select v from tests.fx where k = 'lobby')),
  'active',
  'the run is active'
);

select is(
  (select mode::text from public.runs
    where lobby_id = (select v from tests.fx where k = 'lobby')),
  'arcade',
  'the run is arcade'
);

select is(
  (select count(*)::int from public.matches m
     join public.runs r on r.id = m.run_id
    where r.lobby_id = (select v from tests.fx where k = 'lobby')),
  1,
  'starting a run produces exactly one match'
);

select is(
  (select seq::int from public.matches where id = (select v from tests.fx where k = 'match')),
  1,
  'the match is seq 1'
);

-- The game moves it to playing. A match sitting in setup is a normal transient
-- state; a match stuck there is a game whose setup failed.
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'match')),
  'setup',
  'the match is created in setup, for the game to take over'
);

select is(
  (select game from public.matches where id = (select v from tests.fx where k = 'match')),
  'auction_team_builder',
  'the match carries the game it was started for'
);

-- ---------------------------------------------------------------- the seats --

select is(
  (select count(*)::int from public.run_participants rp
     join public.runs r on r.id = rp.run_id
    where r.lobby_id = (select v from tests.fx where k = 'lobby')),
  4,
  'one run_participants row per current member'
);

select is(
  (select array_agg(rp.seat order by rp.seat) from public.run_participants rp
     join public.runs r on r.id = rp.run_id
    where r.lobby_id = (select v from tests.fx where k = 'lobby')),
  array[0, 1, 2, 3]::smallint[],
  'seats are 0..n-1, unique, with no gaps'
);

select set_eq(
  $$ select rp.user_id from public.run_participants rp
       join public.runs r on r.id = rp.run_id
       join public.lobbies l on l.id = r.lobby_id
      where l.id = (select v from tests.fx where k = 'lobby') $$,
  $$ select v from tests.fx where k in ('a','b','c','d') $$,
  'the snapshot covers exactly the roster that was in the room'
);

-- ------------------------------------------------- a second start is refused --

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby')),
  'P0001', 'run_already_active',
  'a second start against a lobby with an active run is refused'
);

select tests.act_as_admin();
select is(
  (select count(*)::int from public.runs
    where lobby_id = (select v from tests.fx where k = 'lobby')),
  1,
  'and no second run was created'
);

-- The index is what actually adjudicates that under concurrency.
select has_index('public', 'runs', 'runs_one_active',
  'the partial unique index that decides a concurrent start exists');
select index_is_unique('public', 'runs', 'runs_one_active',
  'and it is unique');

-- ---------------------------------------------------- leaving does not erase --

-- run_participants has no foreign key to lobby_members, deliberately (0003).
-- Walking out must not delete a player out of a run in progress.
update public.run_participants
   set score = 7
 where user_id = (select v from tests.fx where k = 'd');

insert into tests.num (k, v)
select 'seat_d', rp.seat
  from public.run_participants rp
  join public.runs r on r.id = rp.run_id
 where r.lobby_id = (select v from tests.fx where k = 'lobby')
   and rp.user_id = (select v from tests.fx where k = 'd');

select tests.act_as((select v from tests.fx where k = 'd'));
select public.leave_lobby((select v from tests.fx where k = 'lobby'));
select tests.act_as_admin();

select is(
  (select rp.seat::int from public.run_participants rp
     join public.runs r on r.id = rp.run_id
    where r.lobby_id = (select v from tests.fx where k = 'lobby')
      and rp.user_id = (select v from tests.fx where k = 'd')),
  (select v from tests.num where k = 'seat_d'),
  'a player who leaves mid-run keeps the seat they were dealt'
);

select is(
  (select score from public.run_participants rp
     join public.runs r on r.id = rp.run_id
    where r.lobby_id = (select v from tests.fx where k = 'lobby')
      and rp.user_id = (select v from tests.fx where k = 'd')),
  7,
  'and their score stands'
);

-- ------------------------------------------------------------ finish_match --

select private.finish_match(
  (select v from tests.fx where k = 'match'),
  jsonb_build_object(
    (select v from tests.fx where k = 'a')::text, 10,
    (select v from tests.fx where k = 'b')::text, 10,
    (select v from tests.fx where k = 'c')::text, 5,
    (select v from tests.fx where k = 'd')::text, 1
  )
);

select is(
  (select raw_score from public.match_players
    where match_id = (select v from tests.fx where k = 'match')
      and user_id = (select v from tests.fx where k = 'a')),
  10::numeric,
  'finish_match writes the raw score it was handed'
);

-- Standard competition ranking: two tied for first are both 1, and the next is 3.
select is(
  (select array_agg(placement order by placement, user_id)
     from public.match_players
    where match_id = (select v from tests.fx where k = 'match')),
  array[1, 1, 3, 4]::smallint[],
  'a tie shares the better placement and the next placement skips'
);

select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'match')),
  'complete',
  'the match ends complete'
);

select isnt(
  (select ended_at from public.matches where id = (select v from tests.fx where k = 'match')),
  null,
  'and is stamped with an end time'
);

select is(
  (select status::text from public.runs
    where lobby_id = (select v from tests.fx where k = 'lobby')),
  'finished',
  'an arcade run is one match, so finishing the match finishes the run'
);

-- ----------------------------------------------- closing takes the game down --

insert into tests.fx (k, v)
values ('e', tests.mkuser('ed')), ('f', tests.mkuser('flo'));

insert into tests.fx (k, v)
values ('lobby2', tests.mklobby(array[
  (select v from tests.fx where k = 'e'),
  (select v from tests.fx where k = 'f')
]));

insert into tests.fx (k, v)
select 'match2', (public.start_run(
  (select v from tests.fx where k = 'lobby2'), 'arcade', 'auction_team_builder')).id;

select tests.act_as((select v from tests.fx where k = 'e'));
select public.close_lobby((select v from tests.fx where k = 'lobby2'));
select tests.act_as_admin();

select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'match2')),
  'abandoned',
  'closing a room with a match in flight abandons the match'
);

select is(
  (select status::text from public.runs
    where lobby_id = (select v from tests.fx where k = 'lobby2')),
  'abandoned',
  'and abandons the run'
);

-- A closed room cannot start a new one.
select tests.act_as((select v from tests.fx where k = 'e'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby2')),
  'P0001', 'lobby_closed',
  'a closed room cannot start a run'
);

-- ------------------------------------------------------------ player counts --

-- One member: the platform's floor. Per-game minimums are the game's business.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('g', tests.mkuser('gus'));
insert into tests.fx (k, v)
values ('lobby3', tests.mklobby(array[(select v from tests.fx where k = 'g')]));

select tests.act_as((select v from tests.fx where k = 'g'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby3')),
  'P0001', 'bad_player_count',
  'a one-person room cannot start a run'
);

-- Five members: join_lobby caps at four, so this state is constructed rather
-- than reachable. The check is the last line of defence if that cap ever moves.
select tests.act_as_admin();
insert into public.lobby_members (lobby_id, user_id)
select (select v from tests.fx where k = 'lobby3'), v
  from tests.fx where k in ('a', 'b', 'c', 'd');

select tests.act_as((select v from tests.fx where k = 'g'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby3')),
  'P0001', 'bad_player_count',
  'a five-person room cannot start a run'
);

-- ----------------------------------------------- a host who is not in the room --

-- Only constructible: leave_lobby migrates the host away or closes the room.
-- The guard exists because host_id is durable and membership is not.
select tests.act_as_admin();
update public.lobby_members
   set left_at = now()
 where lobby_id = (select v from tests.fx where k = 'lobby3')
   and user_id = (select v from tests.fx where k = 'g');

select tests.act_as((select v from tests.fx where k = 'g'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$,
         (select v from tests.fx where k = 'lobby3')),
  '42501', 'not_a_member',
  'a host who is no longer in the room cannot start a run'
);

select * from finish();
rollback;
