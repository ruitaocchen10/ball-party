-- Tests for QB Season Builder's run loop, first slice: starting a run, dealing
-- the first spin, and reading the run's state (migration 0120). See issue #74.
--
-- Everything here goes through the public calls a client makes —
-- start_solo_run, qb_season_builder.start, qb_season_builder.state — as a real
-- player or a guest, with RLS in force. The ratings are a small known fixture
-- (tests.qsb_fixtures) rather than production data, so no assertion depends on
-- a tuned value.

begin;
select plan(22);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina')),
       ('stranger', tests.mkuser('sten'));

select tests.act_as_admin();
select tests.qsb_fixtures();

-- ------------------------------------------------------------ starting a run --

insert into tests.fx (k, v)
select 'm', tests.qsb_start((select v from tests.fx where k = 'a'));

select is(
  (select (qb_season_builder.state((select v from tests.fx where k = 'm'))).phase),
  'picking',
  'a freshly started run is waiting for a pick'
);
select is(
  (select (qb_season_builder.state((select v from tests.fx where k = 'm'))).current_round::int),
  1,
  'it is on round 1'
);
select is(
  (select (qb_season_builder.state((select v from tests.fx where k = 'm'))).round_count::int),
  6,
  'of six'
);
select is(
  (select (qb_season_builder.state((select v from tests.fx where k = 'm'))).mode),
  'visible',
  'the mode defaults to visible'
);
select is(
  (select (qb_season_builder.state((select v from tests.fx where k = 'm'))).respin_used),
  false,
  'and the one respin has not been spent'
);
select is(
  (select (qb_season_builder.state((select v from tests.fx where k = 'm'))).picks),
  '[]'::jsonb,
  'and nothing has been picked'
);

select tests.act_as_admin();
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'm')),
  'playing',
  'the match is playing once it is dealt'
);

-- The mode is chosen at the start. There is no call that changes it afterwards,
-- so the lock is asserted from the other side: what was chosen is what is read,
-- and a dealt run cannot be started a second time to choose again.
insert into tests.fx (k, v)
select 'hidden', tests.qsb_start((select v from tests.fx where k = 'a'), 'hidden');
select is(
  (select (qb_season_builder.state((select v from tests.fx where k = 'hidden'))).mode),
  'hidden',
  'hidden mode is what a player who chose it is given'
);

select throws_ok(
  format($$ select qb_season_builder.start(%L, 'visible') $$, (select v from tests.fx where k = 'hidden')),
  'P0001', 'match_not_setup',
  'a dealt run cannot be started again, so its mode cannot be re-chosen'
);

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  $$ select qb_season_builder.start((select id from public.start_solo_run('qb_season_builder')), 'blind') $$,
  '22023', 'invalid_mode',
  'a mode other than visible or hidden is refused'
);

-- Starting again always begins a new run: a new match on a new run, and the
-- earlier one is left exactly where it was.
select isnt(
  (select v from tests.fx where k = 'm'),
  (select v from tests.fx where k = 'hidden'),
  'starting again creates a new match'
);
select tests.act_as_admin();
select is(
  (select count(distinct run_id)::int from public.matches
    where id in ((select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'hidden'))),
  2,
  'on its own run'
);

-- ---------------------------------------------------------------- the spin --

-- The first spin is a team-season with a qualifying quarterback: one of the
-- four in the fixture, and never the one that has a Supporting Cast and nobody
-- else. Sixty runs, so that missing a real one by luck is not a live risk.
do $$
declare
  v_user  uuid := tests.mkuser('spinner');
  v_match uuid;
  v_bad   int := 0;
  v_seen  text[] := '{}';
  v_key   text;
begin
  for i in 1 .. 60 loop
    v_match := tests.qsb_start(v_user);
    select franchise_code || season into v_key from qb_season_builder.state(v_match);
    if v_key not in ('kan2018', 'kan2019', 'nwe2017', 'phi2017') then
      v_bad := v_bad + 1;
    end if;
    if not (v_key = any(v_seen)) then
      v_seen := v_seen || v_key;
    end if;
  end loop;
  perform tests.act_as_admin();
  insert into tests.num (k, v) values ('spin_bad', v_bad), ('spin_kinds', cardinality(v_seen));
end $$;

select tests.act_as_admin();
select is(
  (select v from tests.num where k = 'spin_bad'), 0,
  'every spin is a team-season that has a qualifying quarterback'
);
select is(
  (select v from tests.num where k = 'spin_kinds'), 4,
  'and every such team-season can come up'
);

-- What state() reports is what was stored, read a second time as the owner
-- through the table itself: a reload, or a second client, sees the same spin.
select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select franchise_code || season from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  (select franchise_code || season from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  'the spin read back is the spin that was dealt'
);
select tests.act_as_admin();
select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm')),
  1,
  'stored once, with the run — reading does not deal'
);

-- The options a visible-mode player picks from: this spin's qualifying
-- quarterbacks with their five qualities, and the team's Supporting Cast.
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 1::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select options from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  '{
    "quarterbacks": [
      {"player_id": "FolsNi00", "display_name": "Nick Foles",
       "values": {"accuracy": 78, "arm_talent": 74, "mobility": 45, "iq": 80, "build": 68}},
      {"player_id": "WentCa00", "display_name": "Carson Wentz",
       "values": {"accuracy": 87, "arm_talent": 90, "mobility": 79, "iq": 83, "build": 86}}
    ],
    "supporting_cast": {"value": 69}
  }'::jsonb,
  'a spin offers each qualifying quarterback''s five qualities and the team''s Supporting Cast'
);

-- ---------------------------------------------------------- guests and rules --

select tests.act_as_admin();
insert into tests.fx (k, v)
select 'guest_match', tests.qsb_start((select v from tests.fx where k = 'guest'), 'visible', true);
select is(
  (select phase from qb_season_builder.state((select v from tests.fx where k = 'guest_match'))),
  'picking',
  'a guest can start a run and read it'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select qb_season_builder.state(%L) $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_a_participant',
  'someone else''s run cannot be read through the API'
);
select throws_ok(
  format($$ select qb_season_builder.start(%L) $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_a_participant',
  'nor started by someone who is not in it'
);

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  $$ select qb_season_builder.start((select id from public.start_solo_run('higher_or_lower'))) $$,
  'P0001', 'wrong_game',
  'a match started for another game cannot be dealt as this one'
);

select tests.act_as_admin();
select throws_ok(
  format($$ select qb_season_builder.start(%L) $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_authenticated',
  'without a session there is no identity to start as'
);

select * from finish();
rollback;
