-- Tests for QB Season Builder's modes and for what no client role can reach
-- (issue #74; no migration of its own — the behaviour is 0120-0122's).
--
-- Hidden mode is enforced by what the API returns, not by the UI, so these
-- read the run as the owner would from a browser and assert the numbers are not
-- there. The leak half asserts the ratings, the value each pick was worth and
-- any round not yet opened are unreachable from every client role, and that a
-- client cannot tamper its way to a different mode or another spin.

begin;
select plan(27);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina')),
       ('stranger', tests.mkuser('sten'));

select tests.act_as_admin();
select tests.qsb_fixtures();

-- ---------------------------------------------------------------- hidden mode --

insert into tests.fx (k, v)
select 'h', tests.qsb_start((select v from tests.fx where k = 'a'), 'hidden');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'h'), 1::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));

select is(
  (select count(*)::int from qb_season_builder.state((select v from tests.fx where k = 'h')) b,
          jsonb_array_elements(b.options -> 'quarterbacks') q
    where jsonb_typeof(q -> 'values') = 'null'),
  2,
  'in hidden mode both quarterbacks are on offer and neither shows a quality value'
);
select is(
  (select jsonb_typeof(options -> 'supporting_cast' -> 'value')
     from qb_season_builder.state((select v from tests.fx where k = 'h'))),
  'null',
  'nor does the Supporting Cast'
);
select ok(
  (select options::text !~ '"(accuracy|arm_talent|mobility|iq|build)"'
     from qb_season_builder.state((select v from tests.fx where k = 'h'))),
  'and the options carry no quality at all, not even under another key'
);

select is(
  (select picks from qb_season_builder.pick((select v from tests.fx where k = 'h'), 'accuracy', 'WentCa00')),
  '[{"round": 1, "slot": "accuracy", "franchise_code": "phi", "season": 2017,
     "player_id": "WentCa00", "display_name": "Carson Wentz", "value": null,
     "headshot_url": "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66"}]'::jsonb,
  'a hidden pick records what was taken from whom but not what it was worth'
);

-- A whole hidden run, all six slots filled: still nothing, until it is complete.
insert into tests.fx (k, v)
select 'h6', tests.qsb_start((select v from tests.fx where k = 'a'), 'hidden');
select tests.qsb_fill((select v from tests.fx where k = 'h6'), 6);
select is(
  (select count(*)::int from qb_season_builder.state((select v from tests.fx where k = 'h6')) b,
          jsonb_array_elements(b.picks) p
    where jsonb_typeof(p -> 'value') = 'null'),
  6,
  'with every slot filled, a hidden run has still revealed none of its six values'
);

-- The run completes: the platform marks the match complete, and the values of
-- what was picked are then returned.
select tests.act_as_admin();
select private.finish_match(
  (select v from tests.fx where k = 'h6'),
  jsonb_build_object((select v from tests.fx where k = 'a')::text, 1)
);
select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select jsonb_path_query_array(picks, '$[*].value')
     from qb_season_builder.state((select v from tests.fx where k = 'h6'))),
  '[87, 90, 79, 83, 86, 69]'::jsonb,
  'once the run is complete a hidden run''s values are revealed'
);

insert into tests.fx (k, v)
select 'hg', tests.qsb_start((select v from tests.fx where k = 'guest'), 'hidden', true);
select is(
  (select jsonb_typeof(options -> 'supporting_cast' -> 'value')
     from qb_season_builder.state((select v from tests.fx where k = 'hg'))),
  'null',
  'a guest''s hidden run hides its values the same way'
);

-- ------------------------------------------------------- a client cannot tamper --

-- Every write to the run's tables goes through the definer functions. Try the
-- direct ones a client would reach for — switching to visible, refunding the
-- respin, deleting a spin to force a reroll, writing a pick — and assert none of
-- it took. Local grants make these errors; the hosted defaults would make them
-- silent no-ops under RLS, so the block accepts either and the assertions after
-- it are what count.
select tests.act_as_admin();
insert into tests.fx (k, v)
select 't', tests.qsb_start((select v from tests.fx where k = 'a'), 'hidden');
select qb_season_builder.respin((select v from tests.fx where k = 't'));
select tests.act_as((select v from tests.fx where k = 'a'));
do $$
declare
  v_match uuid := (select v from tests.fx where k = 't');
begin
  begin update public.qb_season_builder_matches set mode = 'visible' where match_id = v_match;
  exception when insufficient_privilege then null; end;
  begin update public.qb_season_builder_matches set respin_used = false where match_id = v_match;
  exception when insufficient_privilege then null; end;
  begin delete from public.qb_season_builder_spins where match_id = v_match;
  exception when insufficient_privilege then null; end;
  begin insert into public.qb_season_builder_picks (match_id, round_number, slot, franchise_code, season, player_id, display_name)
        values (v_match, 1, 'build', 'nwe', 2017, 'BradTo00', 'Tom Brady');
  exception when insufficient_privilege then null; end;
end $$;

select is(
  (select mode from qb_season_builder.state((select v from tests.fx where k = 't'))),
  'hidden',
  'a client cannot switch a hidden run to visible by writing to it'
);
select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 't')),
  'P0001', 'respin_used',
  'nor hand itself back a spent respin'
);
select is(
  (select count(*)::int from public.qb_season_builder_spins where match_id = (select v from tests.fx where k = 't')),
  2,
  'nor delete a spin to reroll it'
);
select is(
  (select jsonb_array_length(picks) from qb_season_builder.state((select v from tests.fx where k = 't'))),
  0,
  'nor write a pick of its own'
);

-- ------------------------------------------------------------------ the leak --

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok('select count(*) from qb_season_builder_private.qb_seasons',   '42501', null,
  'a signed-in player cannot read the quarterback ratings');
select throws_ok('select count(*) from qb_season_builder_private.team_seasons', '42501', null,
  'nor the Supporting Cast ratings');
select throws_ok('select count(*) from qb_season_builder_private.pick_values', '42501', null,
  'nor the value any run''s pick was worth');
select throws_ok(
  format($$ select qb_season_builder_private.board_of(%L) $$, (select v from tests.fx where k = 'h')),
  '42501', null,
  'nor call the projection that decides what a run may see');

set local role anon;
select throws_ok('select count(*) from qb_season_builder_private.qb_seasons',   '42501', null,
  'a signed-out client cannot read the quarterback ratings');
select throws_ok('select count(*) from qb_season_builder_private.team_seasons', '42501', null,
  'nor the Supporting Cast ratings');
select throws_ok('select count(*) from qb_season_builder_private.pick_values', '42501', null,
  'nor any pick''s value');
select throws_ok(
  format($$ select qb_season_builder.state(%L) $$, (select v from tests.fx where k = 'h')),
  '42501', null,
  'nor call the game API at all');

-- The facts behind that, asserted directly because they are what a later
-- migration could widen by accident.
select tests.act_as_admin();
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'qb_season_builder_private'
       and grantee in ('anon', 'authenticated', 'PUBLIC')
  ),
  'no client role holds any privilege on any table in the private schema'
);
select ok(
  not exists (
    select 1 from information_schema.routine_privileges
     where routine_schema = 'qb_season_builder_private'
       and grantee in ('anon', 'authenticated', 'PUBLIC')
  ),
  'or may execute any function in it'
);
select ok(
  not has_schema_privilege('anon', 'qb_season_builder_private', 'usage')
  and not has_schema_privilege('authenticated', 'qb_season_builder_private', 'usage'),
  'or even look inside the schema'
);
select ok(
  not exists (
    select 1 from pg_publication_tables where schemaname = 'qb_season_builder_private'
  ),
  'and none of it is published to Realtime'
);

-- ---------------------------------------------------------------- unspun rounds --

insert into tests.fx (k, v)
select 'mid', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.qsb_fill((select v from tests.fx where k = 'mid'), 2);

select is(
  (select count(*)::int from public.qb_season_builder_spins where match_id = (select v from tests.fx where k = 'mid')),
  3,
  'a run on round 3 can read the three rounds it has opened'
);
select is(
  (select max(round_number)::int from public.qb_season_builder_spins where match_id = (select v from tests.fx where k = 'mid')),
  3,
  'and nothing beyond the round it is on'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is(
  (select (select count(*) from public.qb_season_builder_matches where match_id = (select v from tests.fx where k = 'mid'))
        + (select count(*) from public.qb_season_builder_spins   where match_id = (select v from tests.fx where k = 'mid'))
        + (select count(*) from public.qb_season_builder_picks   where match_id = (select v from tests.fx where k = 'mid')))::int,
  0,
  'a different player reaches none of the run''s rows'
);
set local role anon;
select is(
  (select (select count(*) from public.qb_season_builder_matches where match_id = (select v from tests.fx where k = 'mid'))
        + (select count(*) from public.qb_season_builder_spins   where match_id = (select v from tests.fx where k = 'mid'))
        + (select count(*) from public.qb_season_builder_picks   where match_id = (select v from tests.fx where k = 'mid')))::int,
  0,
  'nor does a signed-out client'
);
select tests.act_as_admin();

select * from finish();
rollback;
