-- Tests for QB Season Builder's link between the quarterback's line and his team's record: a
-- model can carry a `wins_link` (a correlation, `rho`) and output_value draws the `wins` noise
-- that far along the quarterback's rate draws. Migration 0144 (the shipped value arrives with the
-- data in 0145).
--
-- Uses the small season model of tests.qsb_model_fixtures, in which wins are 0.2 x supporting_cast
-- plus a noise that is linear in its uniform draw, so the wins draw can be read straight off
-- the output.

begin;
select plan(15);

\ir support/harness.psql

select tests.act_as_admin();

-- The model in force, before the fixtures replace it.
select ok(
  (select count(*) = 1 and bool_and(weight > 0 and weight < 1) from qb_season_builder_private.season_model_formulas
    where formula = 'wins_link' and term = 'rho'),
  'the shipped model carries a wins link, a correlation between 0 and 1'
);

-- ------------------------------------------------------------ the normal scores --

select ok(
  abs(qb_season_builder_private.norm_cdf(0) - 0.5) < 1e-7
  and abs(qb_season_builder_private.norm_cdf(1.96) - 0.9750021) < 1e-6
  and abs(qb_season_builder_private.norm_cdf(-1.5) + qb_season_builder_private.norm_cdf(1.5) - 1) < 1e-7,
  'norm_cdf is the normal CDF: 0.5 at 0, 0.975 at 1.96 and symmetric'
);

select ok(
  abs(qb_season_builder_private.norm_inv(0.975) - 1.959964) < 1e-5
  and abs(qb_season_builder_private.norm_inv(0.5)) < 1e-9
  and abs(qb_season_builder_private.norm_inv(0.1) + qb_season_builder_private.norm_inv(0.9)) < 1e-9,
  'norm_inv is its inverse: 1.96 at 0.975, 0 at 0.5 and antisymmetric'
);

select ok(
  (select max(abs(qb_season_builder_private.norm_cdf(qb_season_builder_private.norm_inv(p)) - p))
     from unnest(array[0.000001, 0.0001, 0.01, 0.1, 0.3, 0.5, 0.7, 0.9, 0.99, 0.9999, 0.999999]) p) < 1e-6,
  'norm_cdf(norm_inv(p)) is p, into both tails'
);

select ok(
  qb_season_builder_private.norm_inv(0) between -7 and -5
  and qb_season_builder_private.norm_inv(1) between 5 and 7
  and qb_season_builder_private.norm_cdf(-40) between 0 and 1e-12
  and qb_season_builder_private.norm_cdf(40) = 1,
  'the ends are finite: a draw of exactly 0 or 1 does not blow up'
);

-- ------------------------------------------------------------- the link itself --

select tests.qsb_model_fixtures(1, 1, 0);

create temp table seeds as select s::bigint as seed from generate_series(1, 20000) s;
create temp table v as select '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":50}'::jsonb as v;

-- The line the wins draw is pulled toward, exactly as output_value builds it.
create temp table plain as
select seed,
       qb_season_builder_private.output_value('wins', v.v, seed) as wins,
       qb_season_builder_private.output_value('ypa', v.v, seed) as ypa,
       (qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(seed, 'noise:ypa'))
        + qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(seed, 'noise:td_rate'))
        - qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(seed, 'noise:int_rate'))
        + qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(seed, 'noise:comp_pct'))) / 2 as line
  from seeds cross join v;

select ok(
  (select abs(corr(wins, line)) < 0.03 from plain),
  'with no link the record is independent of the line (the fixture model has none)'
);

-- rho = 0 is no link at all.
insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
values ('wins_link', 'rho', 0);

select is(
  (select array_agg(qb_season_builder_private.output_value('wins', v.v, seed) order by seed) from seeds cross join v),
  (select array_agg(wins order by seed) from plain),
  'a link of 0 draws exactly what no link does'
);

update qb_season_builder_private.season_model_formulas set weight = 0.6
 where formula = 'wins_link' and term = 'rho';

create temp table linked as
select p.seed, qb_season_builder_private.output_value('wins', v.v, p.seed) as wins, p.line
  from plain p cross join v;

select ok(
  (select corr(wins, line) from linked) between 0.55 and 0.62,
  'with a link of 0.6 the record follows the line: a correlation of about 0.6 (0.977 x 0.6 through the CDF)'
);

select ok(
  abs((select stddev(wins) from linked) / (select stddev(wins) from plain) - 1) < 0.03,
  'the record''s own spread is unchanged by the link'
);

select ok(
  abs((select avg(wins) from linked) - (select avg(wins) from plain)) < 0.05,
  'and so is its average'
);

select ok(
  (select bool_and(wins between 8 - 0.0001 and 12 + 0.0001) and min(wins) < 8.2 and max(wins) > 11.8 from linked),
  'the record still spans the whole spread of its residual table (10 +/- 2 here), and no more'
);

select is(
  (select array_agg(qb_season_builder_private.output_value('ypa', v.v, seed) order by seed) from seeds cross join v),
  (select array_agg(ypa order by seed) from plain),
  'no other output is touched by it'
);

select is(
  (select array_agg(qb_season_builder_private.output_value('wins', v.v, seed) order by seed) from seeds cross join v),
  (select array_agg(wins order by seed) from linked),
  'a season is still a pure function of the values and the seed'
);

-- ------------------------------------------------------------- the constraint --

select lives_ok(
  $$ update qb_season_builder_private.season_model_formulas set weight = 0.3
      where formula = 'wins_link' and term = 'rho' $$,
  'the link is an ordinary formula row'
);

select throws_ok(
  $$ insert into qb_season_builder_private.season_model_formulas (formula, term, weight)
     values ('wins_links', 'rho', 0.3) $$,
  '23514', null,
  'but a formula the model does not know is still refused'
);

select * from finish();
rollback;
