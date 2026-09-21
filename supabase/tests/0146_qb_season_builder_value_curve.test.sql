-- Tests for QB Season Builder's difficulty setting: a model can carry a `value_curve` (a pivot
-- and a slope) and output_value counts every value through it: in full up to the pivot, and above
-- it only `slope` of each point. Migration 0146 (the shipped curve itself arrives with the data
-- in 0147).
--
-- Uses the small season model of tests.qsb_model_fixtures, with no noise: ypa is 2 + 0.1 x
-- arm_talent and wins are 0.2 x supporting_cast, so what a value counted for can be read
-- straight off the output.

begin;
select plan(13);

\ir support/harness.psql

select tests.act_as_admin();

-- The model in force, before the fixtures replace it.
select ok(
  (select count(*) = 2
      and bool_and(weight > 0 and weight < 100 and (term <> 'slope' or weight <= 1))
     from qb_season_builder_private.season_model_formulas
    where formula = 'value_curve' and term in ('pivot', 'slope')),
  'the shipped model carries a value curve: a pivot below 100 and a slope of at most 1'
);

select tests.qsb_model_fixtures();

create temp table v as
select a as arm, jsonb_build_object('accuracy', 50, 'arm_talent', a, 'mobility', 50, 'iq', 50, 'build', 50, 'supporting_cast', 50) as vals
  from generate_series(0, 99) a;

-- ------------------------------------------------------------ without a curve --

select ok(
  abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 90), 1) - 11.0) < 1e-9,
  'with no curve a value of 90 counts as 90 (2 + 0.1 x 90)'
);

-- A pivot with no slope (or the other way round) is not a curve.
insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
values ('value_curve', 'pivot', 70);

select ok(
  abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 90), 1) - 11.0) < 1e-9,
  'half a curve leaves every value alone'
);

-- ---------------------------------------------------------------- with a curve --

insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
values ('value_curve', 'slope', 0.5);

select ok(
  abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 90), 1) - 10.0) < 1e-9,
  'above the pivot only the slope of each point counts: 90 plays like 80 (pivot 70, slope 0.5)'
);

select ok(
  abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 20), 1) - 4.0) < 1e-9
  and abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 60), 1) - 8.0) < 1e-9
  and abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 70), 1) - 9.0) < 1e-9,
  'at or below the pivot a value counts in full'
);

select ok(
  abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 99), 1) - 10.45) < 1e-9,
  '99 plays like 84.5 (pivot 70, slope 0.5): 2 + 0.1 x 84.5'
);

select ok(
  (select bool_and(y >= coalesce(lag_y, 0))
     from (select y, lag(y) over (order by arm) as lag_y
             from (select arm, qb_season_builder_private.output_value('ypa', vals, 1) y from v) s) t),
  'a better value never counts for less'
);

-- Every slot reads the same effective values, the record's as well as the line's.
select ok(
  abs(qb_season_builder_private.output_value('wins', jsonb_build_object('accuracy', 50, 'arm_talent', 50, 'mobility', 50,
    'iq', 50, 'build', 50, 'supporting_cast', 90), 1) - 16.0) < 1e-9,
  'the record reads it too: a Supporting Cast of 90 plays like 80 (0.2 x 80)'
);

update qb_season_builder_private.season_model_formulas set weight = 1
 where formula = 'value_curve' and term = 'slope';

select ok(
  abs(qb_season_builder_private.output_value('ypa', (select vals from v where arm = 90), 1) - 11.0) < 1e-9,
  'a slope of 1 is no curve'
);

-- ---------------------------------------------------- the game still generates --

update qb_season_builder_private.season_model_formulas set weight = 0.85
 where formula = 'value_curve' and term = 'slope';

select ok(
  (select bool_and((g ->> 'score')::numeric between 0 and 100 and jsonb_typeof(g -> 'stat_line') = 'object')
     from (select qb_season_builder_private.generate_season(vals, s) as g
             from v cross join generate_series(1, 5) s where arm in (0, 50, 99)) x),
  'a season is still generated, and scored 0 to 100, with the curve in place'
);

select is(
  qb_season_builder_private.generate_season((select vals from v where arm = 90), 7),
  qb_season_builder_private.generate_season((select vals from v where arm = 90), 7),
  'and is still a pure function of the values and the seed'
);

-- ------------------------------------------------------------- the constraint --

select lives_ok(
  $$ update qb_season_builder_private.season_model_formulas set weight = 60
      where formula = 'value_curve' and term = 'pivot' $$,
  'the curve rows are ordinary formula rows'
);

select throws_ok(
  $$ insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
     values ('value_curves', 'pivot', 1) $$,
  '23514', null,
  'but a formula the model does not know is still refused'
);

select * from finish();
rollback;
