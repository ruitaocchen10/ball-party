-- Tests for QB Season Builder's soft ceiling on the score: a model can carry a `score_curve`
-- (a start and an exponent) and generate_season holds the mixed score to it. Migration 0141
-- (the shipped curve itself arrives with the data in 0142).
--
-- Uses the small season model of tests.qsb_model_fixtures, in which wins are exactly
-- 0.2 x supporting_cast, so a run of casts from 25 to 99 walks the score from the bottom of
-- the fixture's distributions to the top.

begin;
select plan(12);

\ir support/harness.psql

select tests.act_as_admin();

-- The model in force, before the fixtures replace it.
select ok(
  (select count(*) = 2 from qb_season_builder_private.season_model_formulas
    where formula = 'score_curve' and term in ('start', 'exponent')),
  'the shipped model carries a score curve: a start and an exponent'
);

-- ------------------------------------------------ without a curve, as before --

select tests.qsb_model_fixtures();

create temp table builds as
select c as cast_, jsonb_build_object('accuracy', 50, 'arm_talent', 50, 'mobility', 50,
                                      'iq', 50, 'build', 50, 'supporting_cast', c) as v
  from generate_series(25, 99, 6) c;

create temp table plain as
select cast_, (qb_season_builder_private.generate_season(v, 1) ->> 'score')::numeric as score
  from builds;

select ok(
  (select count(*) filter (where score <= 40) > 0 and count(*) filter (where score > 40) > 0 from plain),
  'the fixture builds run from under 40 to over it, so a curve starting there has both sides to act on'
);

select ok(
  (select bool_and(
     (select sum((p ->> 'points')::numeric) from jsonb_array_elements(g -> 'breakdown') p) = (g ->> 'score')::numeric)
     from (select qb_season_builder_private.generate_season(v, 1) as g from builds) s),
  'without a curve the breakdown adds up to the score'
);

-- An exponent with no start (or the other way round) is not a curve.
insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
values ('score_curve', 'exponent', 2);

select is(
  (select array_agg((qb_season_builder_private.generate_season(v, 1) ->> 'score')::numeric order by cast_) from builds),
  (select array_agg(score order by cast_) from plain),
  'half a curve leaves every score alone'
);

-- ---------------------------------------------------------------- with a curve --

insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
values ('score_curve', 'start', 40);

create temp table curved as
select b.cast_, p.score as raw,
       (qb_season_builder_private.generate_season(b.v, 1) ->> 'score')::numeric as score
  from builds b join plain p using (cast_);

select ok(
  (select bool_and(score = raw) from curved where raw <= 40),
  'at or below the start a score is unchanged'
);

select ok(
  (select bool_and(score < raw and abs(score - (40 + 60 * power((raw - 40) / 60, 2))) <= 0.25)
     from curved where raw > 40),
  'above it the score is start + (100 - start) * ((score - start) / (100 - start)) ^ exponent'
);

select ok(
  (select bool_and(score >= coalesce(lag_score, 0))
     from (select score, lag(score) over (order by cast_) as lag_score from curved) s),
  'a better build never scores worse for the curve'
);

select ok(
  (select bool_and(
     (select sum((p ->> 'points')::numeric) from jsonb_array_elements(g -> 'breakdown') p) = (g ->> 'score')::numeric)
     from (select qb_season_builder_private.generate_season(v, 1) as g from builds) s),
  'with one the breakdown still adds up to the score'
);

-- The ends stay where they are: better than every real season is 100, better than none is 0.
update qb_season_builder_private.season_model_distributions set value = value - 100;
select is(
  (qb_season_builder_private.generate_season((select v from builds where cast_ = 99), 1) ->> 'score')::numeric,
  100.0,
  'a season better than every real one still scores exactly 100'
);

update qb_season_builder_private.season_model_distributions set value = value + 200;
select is(
  (qb_season_builder_private.generate_season((select v from builds where cast_ = 99), 1) ->> 'score')::numeric,
  0.0,
  'and one better than none still scores 0'
);

-- ------------------------------------------------------------- the constraint --

select lives_ok(
  $$ update qb_season_builder_private.season_model_formulas set weight = 50
      where formula = 'score_curve' and term = 'start' $$,
  'the curve rows are ordinary formula rows'
);

select throws_ok(
  $$ insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
     values ('score_curves', 'start', 1) $$,
  '23514', null,
  'but a formula the model does not know is still refused'
);

select * from finish();
rollback;
