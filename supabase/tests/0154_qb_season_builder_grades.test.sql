-- Tests for QB Season Builder's letter grades (migration 0154). A client is told
-- a grade, A+ to F, wherever it used to be told a blended value; the season model
-- still runs on the values, which are untouched.
--
-- The cut-off table is asserted at every boundary, then through the public calls
-- a player makes, and last through a result saved before the migration, which
-- still carries a number on each pick and must come out graded.

begin;
select plan(7);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava'));

select tests.act_as_admin();
select tests.qsb_fixtures();

-- ---------------------------------------------------------------- grade_of --

select is(
  (select array_agg(qb_season_builder_private.grade_of(v) order by v desc)
     from unnest(array[99, 95, 94, 90, 89, 86, 85, 82, 81, 78, 77, 74, 73, 70,
                       69, 65, 64, 60, 59, 55, 54, 50, 49, 45, 44, 0]) v),
  array['A+', 'A+', 'A', 'A', 'A-', 'A-', 'B+', 'B+', 'B', 'B', 'B-', 'B-', 'C+', 'C+',
        'C', 'C', 'C-', 'C-', 'D+', 'D+', 'D', 'D', 'D-', 'D-', 'F', 'F'],
  'every boundary falls where the table says: five points a grade, F at 44 and below'
);
select is(
  qb_season_builder_private.grade_of(null),
  null,
  'and a value that is not there has no grade'
);

-- ------------------------------------------------------------ what a client sees --

insert into tests.fx (k, v)
select 'v', tests.qsb_start((select v from tests.fx where k = 'a'), 'visible');
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'v'), 1::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));

select is(
  (select q -> 'grades'
     from qb_season_builder.state((select v from tests.fx where k = 'v')) b,
          jsonb_array_elements(b.options -> 'quarterbacks') q
    where q ->> 'player_id' = 'WentCa00'),
  '{"accuracy": "A-", "arm_talent": "A", "mobility": "B", "iq": "B+", "build": "A-"}'::jsonb,
  'a visible spin shows each quality as its grade (87, 90, 79, 83 and 86)'
);
select is(
  (select options -> 'supporting_cast' -> 'grade'
     from qb_season_builder.state((select v from tests.fx where k = 'v'))),
  '"C"'::jsonb,
  'and the Supporting Cast as its grade (69)'
);
select ok(
  (select b.options::text !~ '"(value|values)"' and b.options::text !~ ':\s*[0-9]'
     from qb_season_builder.state((select v from tests.fx where k = 'v')) b),
  'and no number is anywhere in what the spin sends'
);

-- ------------------------------------------------- a result saved before grades --

-- What `finish` stored before this migration: a pick carries `value`, a number.
select tests.act_as_admin();
insert into qb_season_builder_private.season_results (match_id, seed, mode, score, result)
values (
  (select v from tests.fx where k = 'v'), 1, 'visible', 50,
  jsonb_build_object(
    'match_id', (select v from tests.fx where k = 'v'), 'mode', 'visible',
    'picks', jsonb_build_array(
      jsonb_build_object('round', 1, 'slot', 'iq', 'franchise_code', 'nwe', 'season', 2017,
                         'player_id', 'BradTo00', 'display_name', 'Tom Brady', 'value', 99),
      jsonb_build_object('round', 2, 'slot', 'supporting_cast', 'franchise_code', 'nyj', 'season', 2020,
                         'player_id', null, 'display_name', null, 'value', 31),
      jsonb_build_object('round', 3, 'slot', 'accuracy', 'franchise_code', 'phi', 'season', 2017,
                         'player_id', 'WentCa00', 'display_name', 'Carson Wentz', 'grade', 'A-')
    )
  )
);

set local role anon;
select is(
  (select jsonb_path_query_array(qb_season_builder.result((select v from tests.fx where k = 'v')), '$.picks[*].grade')),
  '["A+", "F", "A-"]'::jsonb,
  'a stored result is graded on the way out, in the order it was saved, and a pick already graded is left alone'
);
select ok(
  (select qb_season_builder.result((select v from tests.fx where k = 'v'))::text !~ '"value"'),
  'and none of its picks still carries a number'
);

select * from finish();
rollback;
