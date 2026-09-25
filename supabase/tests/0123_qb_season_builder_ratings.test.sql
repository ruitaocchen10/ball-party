-- Tests for QB Season Builder's ratings pipeline load (issue #75): the real
-- values are in the finished-values tables and playable, the Madden ratings they
-- were blended from are unreachable by every client role and absent from every
-- response, and the hand overrides table exists and is applied.
--
-- The first half reads the rows 0124 loaded, BEFORE tests.qsb_fixtures() clears
-- them: it asserts that a local run after a reset really has data to play, and
-- deliberately nothing about any value's size, which a retune may change. The
-- second half runs on the small fixtures like the rest of the suites.

begin;
select plan(36);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina')),
       ('stranger', tests.mkuser('sten'));

select tests.act_as_admin();

-- ------------------------------------------------------------ the real data --

select is(
  (select count(distinct season)::int from qb_season_builder_private.qb_seasons),
  20,
  'every season from 2006 to 2025 has qualifying quarterbacks loaded'
);
select is(
  (select count(distinct season)::int from qb_season_builder_private.team_seasons),
  20,
  'and a Supporting Cast'
);
select cmp_ok(
  (select count(*)::int from qb_season_builder_private.qb_seasons), '>=', 700,
  'with hundreds of quarterback-seasons, not a fixture''s handful'
);
select ok(
  exists (
    select 1 from qb_season_builder_private.qb_seasons
     where franchise_code = 'kan' and season = 2018 and player_id = 'MahoPa00'
  ),
  'and a quarterback-season anyone would look for is in it'
);
select is(
  (select count(*)::int from qb_season_builder_private.team_seasons t
    where t.season between 2006 and 2025
      and (select count(*) from qb_season_builder_private.team_seasons x where x.season = t.season) < 30),
  0,
  'each season has a Supporting Cast for essentially the whole league'
);

-- A player's run on the real data: dealt a spin, values shown in visible mode,
-- and playable start to finish through the public calls.
insert into tests.fx (k, v)
select 'real', tests.qsb_start((select v from tests.fx where k = 'a'), 'visible');

select ok(
  (select jsonb_array_length(options -> 'quarterbacks') >= 1
      and jsonb_typeof(options -> 'supporting_cast' -> 'grade') = 'string'
     from qb_season_builder.state((select v from tests.fx where k = 'real'))),
  'a run started on the real data is dealt a spin with a quarterback and a cast grade'
);

do $$
declare
  v_match uuid := (select v from tests.fx where k = 'real');
  v_slots constant text[] := array['supporting_cast', 'accuracy', 'arm_talent', 'mobility', 'iq', 'build'];
  v_pid   text;
  v_i     int;
begin
  for v_i in 1 .. 6 loop
    select q ->> 'player_id' into v_pid
      from qb_season_builder.state(v_match) b, jsonb_array_elements(b.options -> 'quarterbacks') q
     limit 1;
    perform qb_season_builder.pick(
      v_match, v_slots[v_i], case when v_slots[v_i] = 'supporting_cast' then null else v_pid end);
  end loop;
end $$;

select is(
  (select phase from qb_season_builder.state((select v from tests.fx where k = 'real'))),
  'ready_to_finish',
  'and can be played through all six rounds on real spins'
);
select ok(
  (select bool_and(jsonb_typeof(p -> 'grade') = 'string')
     from qb_season_builder.state((select v from tests.fx where k = 'real')) b,
          jsonb_array_elements(b.picks) p),
  'every pick carries the grade its blended value earned'
);

-- What a client was told, in either mode, names no source rating.
insert into tests.fx (k, v)
select 'real_hidden', tests.qsb_start((select v from tests.fx where k = 'a'), 'hidden');
select ok(
  (select bool_and(s.j !~* '(madden|overall|throw_?power|throw_?accuracy|edition)')
     from (select to_jsonb(b)::text as j from qb_season_builder.state((select v from tests.fx where k = 'real')) b
            union all
           select to_jsonb(b)::text from qb_season_builder.state((select v from tests.fx where k = 'real_hidden')) b) s),
  'no response carries a source rating, its name, or an edition'
);

-- ------------------------------------------------- the Madden table is private --

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok('select count(*) from qb_season_builder_private.madden_ratings', '42501', null,
  'a signed-in player cannot read the Madden ratings');
select throws_ok('select count(*) from qb_season_builder_private.rating_overrides', '42501', null,
  'nor the hand overrides');
select throws_ok('select qb_season_builder_private.apply_rating_overrides()', '42501', null,
  'nor apply them');

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok('select count(*) from qb_season_builder_private.madden_ratings', '42501', null,
  'a guest cannot read the Madden ratings');
select throws_ok('select count(*) from qb_season_builder_private.rating_overrides', '42501', null,
  'nor the hand overrides');

set local role anon;
select throws_ok('select count(*) from qb_season_builder_private.madden_ratings', '42501', null,
  'a signed-out client cannot read the Madden ratings');
select throws_ok('select count(*) from qb_season_builder_private.rating_overrides', '42501', null,
  'nor the hand overrides');

select tests.act_as_admin();
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'qb_season_builder_private' and table_name = 'madden_ratings'
       and grantee in ('anon', 'authenticated', 'PUBLIC', 'service_role')
  ),
  'no client role holds a privilege on the Madden table, not even by inheritance from a default grant'
);
select ok(
  (select relrowsecurity from pg_class
    where oid = 'qb_season_builder_private.madden_ratings'::regclass),
  'and row level security is on for it as a second lock'
);
select cmp_ok(
  (select count(*)::int from qb_season_builder_private.madden_ratings), '>', 0,
  'yet the source ratings are loaded where the pipeline put them'
);

-- The surface a client can reach: no function, view, table or column outside the
-- private schema mentions the source. A later migration that wired one in would
-- fail here before it shipped a number.
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'qb_season_builder') and p.prosrc ~* 'madden'
  ),
  'no function in an exposed schema reads the Madden ratings'
);
select ok(
  not exists (
    select 1 from pg_views
     where schemaname in ('public', 'qb_season_builder') and definition ~* 'madden'
  ),
  'no view does'
);
select ok(
  not exists (
    select 1 from information_schema.columns
     where table_schema in ('public', 'qb_season_builder')
       and (column_name ~* 'madden' or table_name ~* 'madden')
  ),
  'and no exposed table or column is named for it'
);
select ok(
  not exists (
    select 1 from pg_attribute a
      join pg_type t on t.oid = a.atttypid
      join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'qb_season_builder' and t.typtype = 'c' and a.attnum > 0
       and a.attname ~* '(madden|overall|throw_?power|edition)'
  ),
  'and the shape a client receives has no field for a source rating'
);

-- --------------------------------------------------------- the hand overrides --

select tests.qsb_fixtures();

-- Whatever real overrides the pipeline loaded, these tests start from none.
delete from qb_season_builder_private.rating_overrides;
select has_table(
  'qb_season_builder_private', 'rating_overrides',
  'the hand overrides table exists'
);

insert into qb_season_builder_private.rating_overrides (franchise_code, season, player_id, slot, value, reason)
values ('phi', 2017, 'FolsNi00', 'mobility', 90, 'test: a runner the formulas under-rate'),
       ('nwe', 2017, '',         'supporting_cast', 12, 'test: a cast the formulas over-rate');

select is(
  qb_season_builder_private.apply_rating_overrides(),
  2,
  'applying the overrides reports how many values it corrected'
);
select is(
  (select mobility::int from qb_season_builder_private.qb_seasons where player_id = 'FolsNi00'),
  90,
  'a quarterback quality is overwritten'
);
select is(
  (select supporting_cast::int from qb_season_builder_private.team_seasons
    where franchise_code = 'nwe' and season = 2017),
  12,
  'and so is a Supporting Cast'
);
select is(
  (select array[accuracy, arm_talent, iq, build]::int[] from qb_season_builder_private.qb_seasons
    where player_id = 'FolsNi00'),
  array[78, 74, 80, 68],
  'the rest of that quarterback-season is untouched'
);
select is(
  (select mobility::int from qb_season_builder_private.qb_seasons where player_id = 'WentCa00'),
  79,
  'as is everyone else'
);

-- A corrected value is what a player is offered.
select tests.act_as((select v from tests.fx where k = 'a'));
insert into tests.fx (k, v)
select 'over', tests.qsb_start((select v from tests.fx where k = 'a'), 'visible');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'over'), 1::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select q -> 'grades' ->> 'mobility'
     from qb_season_builder.state((select v from tests.fx where k = 'over')) b,
          jsonb_array_elements(b.options -> 'quarterbacks') q
    where q ->> 'player_id' = 'FolsNi00'),
  'A',
  'the game offers the overridden value, as a grade'
);
select tests.act_as_admin();

-- An override that matches nothing is an error, and it changes nothing.
insert into qb_season_builder_private.rating_overrides (franchise_code, season, player_id, slot, value)
values ('phi', 2017, 'WentCa00', 'iq', 1),
       ('phi', 2017, 'NobodyX00', 'iq', 50);
select throws_ok(
  'select qb_season_builder_private.apply_rating_overrides()',
  'P0002', 'override_matches_no_row',
  'an override that matches no row is refused'
);
select is(
  (select iq::int from qb_season_builder_private.qb_seasons where player_id = 'WentCa00'),
  83,
  'and the valid one beside it is not applied either'
);

select throws_ok(
  $$ insert into qb_season_builder_private.rating_overrides (franchise_code, season, player_id, slot, value)
     values ('nwe', 2017, 'BradTo00', 'supporting_cast', 5) $$,
  '23514', null,
  'a Supporting Cast override names no quarterback'
);
select throws_ok(
  $$ insert into qb_season_builder_private.rating_overrides (franchise_code, season, player_id, slot, value)
     values ('nwe', 2017, '', 'iq', 5) $$,
  '23514', null,
  'a quality override always does'
);
select throws_ok(
  $$ insert into qb_season_builder_private.rating_overrides (franchise_code, season, player_id, slot, value)
     values ('nwe', 2017, 'BradTo00', 'iq', 100) $$,
  '23514', null,
  'and an override stays on the 0-99 scale'
);
select throws_ok(
  $$ insert into qb_season_builder_private.rating_overrides (franchise_code, season, player_id, slot, value)
     values ('nwe', 2017, 'BradTo00', 'charisma', 50) $$,
  '23514', null,
  'and names a real slot'
);

select * from finish();
rollback;
