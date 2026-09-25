-- Tests for QB Season Builder's run loop, second slice: picking a source into
-- an open slot and advancing rounds (migration 0121). See issue #74.
--
-- Played through the public calls as a real player and as a guest, with RLS in
-- force. Spins are random by design, so a test that cares which options are on
-- offer pins the round's spin first (tests.qsb_set_spin) and asserts against the
-- fixture's literal values, never against a recomputation.

begin;
select plan(30);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina')),
       ('stranger', tests.mkuser('sten'));

select tests.act_as_admin();
select tests.qsb_fixtures();

-- ------------------------------------------------------ a pick and the round --

insert into tests.fx (k, v)
select 'm', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 1::smallint, 'phi', 2017::smallint);

select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select picks from qb_season_builder.pick((select v from tests.fx where k = 'm'), 'accuracy', 'WentCa00')),
  '[{"round": 1, "slot": "accuracy", "franchise_code": "phi", "season": 2017,
     "player_id": "WentCa00", "display_name": "Carson Wentz", "grade": "A-",
     "headshot_url": "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66"}]'::jsonb,
  'picking one quality of a quarterback on the spin fills that slot with his grade'
);
select is(
  (select current_round::int from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  2,
  'and opens round 2'
);
select tests.act_as_admin();
select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 2),
  1,
  'round 2''s spin is dealt and stored when the round opens'
);
select ok(
  (select franchise_code || season from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 2)
    in ('kan2018', 'kan2019', 'nwe2017', 'phi2017'),
  'and it is a team-season with a qualifying quarterback'
);

-- ------------------------------------------------------------- the choices --

select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 2::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));

select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'accuracy', 'FolsNi00') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'slot_filled',
  'a slot cannot be filled twice, even from a different quarterback'
);
select is(
  (select current_round::int from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  2,
  'and a refused pick does not move the round'
);

select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'mobility', 'MoorMa00') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'source_not_on_spin',
  'a quarterback from a different team-season is not on the spin'
);
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 2::smallint, 'kan', 2018::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'mobility', 'MoorMa00') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'source_not_on_spin',
  'nor is one from the same team in a different year'
);
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 2::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));

select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'mobility') $$, (select v from tests.fx where k = 'm')),
  '22023', 'invalid_source',
  'a quarterback quality needs the quarterback it comes from'
);
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'supporting_cast', 'WentCa00') $$, (select v from tests.fx where k = 'm')),
  '22023', 'invalid_source',
  'and the Supporting Cast comes from the team, not from a quarterback'
);
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'speed', 'WentCa00') $$, (select v from tests.fx where k = 'm')),
  '22023', 'invalid_slot',
  'a slot that does not exist is refused'
);

-- The player chooses which open slot the spin fills: the same spin, a different
-- slot, taken from the other quarterback.
select is(
  (select picks -> 1 from qb_season_builder.pick((select v from tests.fx where k = 'm'), 'iq', 'FolsNi00')),
  '{"round": 2, "slot": "iq", "franchise_code": "phi", "season": 2017,
    "player_id": "FolsNi00", "display_name": "Nick Foles", "grade": "B"}'::jsonb,
  'the player chooses which open slot a spin fills, and from whom'
);

select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 3::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select picks -> 2 from qb_season_builder.pick((select v from tests.fx where k = 'm'), 'supporting_cast')),
  '{"round": 3, "slot": "supporting_cast", "franchise_code": "phi", "season": 2017,
    "player_id": null, "display_name": null, "grade": "C"}'::jsonb,
  'the team''s Supporting Cast is a source of its own'
);

-- ---------------------------------------------------------- finishing the six --

select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 4::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'm'), 'mobility', 'WentCa00');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 5::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.pick((select v from tests.fx where k = 'm'), 'arm_talent', 'FolsNi00');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 6::smallint, 'phi', 2017::smallint);

select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select phase from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  'picking',
  'with one slot open the run is still picking'
);
select is(
  (select picks from qb_season_builder.pick((select v from tests.fx where k = 'm'), 'build', 'WentCa00')),
  '[
    {"round": 1, "slot": "accuracy",        "franchise_code": "phi", "season": 2017, "player_id": "WentCa00", "display_name": "Carson Wentz", "grade": "A-", "headshot_url": "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66"},
    {"round": 2, "slot": "iq",              "franchise_code": "phi", "season": 2017, "player_id": "FolsNi00", "display_name": "Nick Foles",   "grade": "B"},
    {"round": 3, "slot": "supporting_cast", "franchise_code": "phi", "season": 2017, "player_id": null,       "display_name": null,           "grade": "C"},
    {"round": 4, "slot": "mobility",        "franchise_code": "phi", "season": 2017, "player_id": "WentCa00", "display_name": "Carson Wentz", "grade": "B", "headshot_url": "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66"},
    {"round": 5, "slot": "arm_talent",      "franchise_code": "phi", "season": 2017, "player_id": "FolsNi00", "display_name": "Nick Foles",   "grade": "B-"},
    {"round": 6, "slot": "build",           "franchise_code": "phi", "season": 2017, "player_id": "WentCa00", "display_name": "Carson Wentz", "grade": "A-", "headshot_url": "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66"}
  ]'::jsonb,
  'six picks fill six slots, each with the grade of the source it took'
);
select is(
  (select phase from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  'ready_to_finish',
  'a run with every slot filled is ready to finish'
);
select is(
  (select options from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  null::jsonb,
  'and there is no seventh spin to offer'
);
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'accuracy', 'WentCa00') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'draft_complete',
  'nothing more can be picked'
);
select tests.act_as_admin();
select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm')),
  6,
  'six rounds dealt in all, one spin each'
);

-- --------------------------------------------- rounds not yet open are not readable --

insert into tests.fx (k, v)
select 'early', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.act_as_admin();
select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'early')),
  1,
  'a run on round 1 has dealt round 1 and nothing after it'
);

-- Even a spin that somehow existed ahead of its round is not readable: the
-- policy gates on the round, so the guarantee does not rest on the deal alone.
insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
values ((select v from tests.fx where k = 'early'), 2, 1, 'nwe', 2017);

select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'early')),
  1,
  'the owner reads their open round and not a later one'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is_empty(
  format($$ select 1 from public.qb_season_builder_spins where match_id = %L $$, (select v from tests.fx where k = 'early')),
  'a different player reads none of it'
);

set local role anon;
select is_empty(
  format($$ select 1 from public.qb_season_builder_spins where match_id = %L $$, (select v from tests.fx where k = 'early')),
  'and neither does a signed-out client'
);
select tests.act_as_admin();

-- ------------------------------------------------------------------- the rules --

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'accuracy', 'MoorMa00') $$,
         (select id from public.start_solo_run('qb_season_builder'))),
  'P0001', 'match_not_playing',
  'a run that has not been dealt cannot be picked in'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'accuracy', 'WentCa00') $$, (select v from tests.fx where k = 'early')),
  '42501', 'not_a_participant',
  'someone else cannot pick in a run'
);
select tests.act_as_admin();
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'accuracy', 'WentCa00') $$, (select v from tests.fx where k = 'early')),
  '42501', 'not_authenticated',
  'and without a session there is no one to pick'
);

-- --------------------------------------------------------------- guests, walking away --

insert into tests.fx (k, v)
select 'g', tests.qsb_start((select v from tests.fx where k = 'guest'), 'visible', true);
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'g'), 1::smallint, 'nwe', 2017::smallint);
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select is(
  (select picks -> 0 -> 'grade' from qb_season_builder.pick((select v from tests.fx where k = 'g'), 'iq', 'BradTo00')),
  '"A+"'::jsonb,
  'a guest picks through the same call'
);

-- The guest walks away after one pick. Nothing sweeps the run, and its URL — the
-- state call — still answers, with the same round and the same pick.
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select is(
  (select current_round::int from qb_season_builder.state((select v from tests.fx where k = 'g'))),
  2,
  'an abandoned run is still readable by its owner, on the round they left it'
);
select is(
  (select count(*)::int from public.qb_season_builder_picks
    where match_id = (select v from tests.fx where k = 'g')),
  1,
  'with the pick they made, readable through RLS as a guest'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is_empty(
  format($$ select 1 from public.qb_season_builder_picks where match_id = %L $$, (select v from tests.fx where k = 'g')),
  'and no one else can read it'
);

select * from finish();
rollback;
