-- Tests for QB Season Builder's season model load (issue #76): the fit that turns
-- six picked values into a season is in the database as data, complete enough for
-- season generation to read, in step with the finished ratings it was fitted on,
-- and unreachable by every client role.
--
-- Nothing here asserts a coefficient, a threshold or how big any value is: those
-- are tuning, and a retune arrives as a new generated migration. What is asserted
-- is the shape the game will rely on and the relationships that must hold whatever
-- the numbers are (a better build wins more; a rate stays inside its bounds).

begin;
select plan(43);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina'));

select tests.act_as_admin();

-- --------------------------------------------------------------- what is loaded --

select is(
  (select count(*)::int from qb_season_builder_private.season_model_outputs), 8,
  'the model has all eight outputs: the passing line, the rushing line and wins'
);
select is(
  (select count(*)::int from qb_season_builder_private.season_model_coefficients), 8 * 6,
  'each is a formula of all six values'
);
select is(
  (select count(distinct output)::int from qb_season_builder_private.season_model_residuals), 8,
  'each has a real residual spread to draw noise from'
);
select ok(
  not exists (
    select 1 from qb_season_builder_private.season_model_outputs o
     where (select count(*) from qb_season_builder_private.season_model_residuals r
             where r.output = o.output) < 5
  ),
  'made of enough quantiles to be a spread, not a point'
);
select ok(
  not exists (
    select 1
      from qb_season_builder_private.season_model_residuals a
      join qb_season_builder_private.season_model_residuals b
        on b.output = a.output and b.p > a.p and b.residual < a.residual
  ),
  'the residual quantiles never go backwards, so interpolating one is safe'
);
select ok(
  not exists (
    select 1 from qb_season_builder_private.season_model_outputs o
     where not exists (select 1 from qb_season_builder_private.season_model_residuals r
                        where r.output = o.output and r.p = 0)
        or not exists (select 1 from qb_season_builder_private.season_model_residuals r
                        where r.output = o.output and r.p = 1)
  ),
  'and each runs the whole way from p = 0 to p = 1, so noise is bounded by what really happened'
);
select ok(
  not exists (
    select 1 from qb_season_builder_private.season_model_residuals r
     where r.p = 0 and r.residual > 0
  ) and not exists (
    select 1 from qb_season_builder_private.season_model_residuals r
     where r.p = 1 and r.residual < 0
  ),
  'with a real miss on either side of the formula'
);

select results_eq(
  $$ select step from qb_season_builder_private.season_model_playoff_ladder order by rung $$,
  $$ values ('make_playoffs'), ('reach_divisional'), ('reach_conference'),
            ('reach_super_bowl'), ('win_super_bowl') $$,
  'the playoff ladder has a rung for each round, in order'
);
select is(
  (select count(*)::int from qb_season_builder_private.season_model_metrics), 8,
  'the score has the metrics it judges a season on'
);
select is(
  (select count(*)::int from qb_season_builder_private.season_model_awards), 5,
  'there is a threshold for each of the five awards'
);
select ok(
  not exists (select 1 from qb_season_builder_private.season_model_awards where winners < 1),
  'each calibrated on at least one real winner'
);
select results_eq(
  $$ select component from qb_season_builder_private.season_model_distributions
      group by component having count(*) >= 11 order by component $$,
  $$ values ('awards'), ('stat_line'), ('team_success') $$,
  'the three score components each have a real distribution to rank a season against'
);
select is(
  (select count(distinct n)::int from (
     select count(*) as n from qb_season_builder_private.season_model_distributions
      group by component) c),
  1,
  'on the same grid of quantiles'
);
select ok(
  not exists (
    select 1
      from qb_season_builder_private.season_model_distributions a
      join qb_season_builder_private.season_model_distributions b
        on b.component = a.component and b.p > a.p and b.value < a.value
  ),
  'and none of those distributions goes backwards'
);
select results_eq(
  $$ select term from qb_season_builder_private.season_model_formulas
      where formula = 'score' order by term $$,
  $$ values ('awards'), ('stat_line'), ('team_success') $$,
  'the score is a weighted mix of the three components'
);
select ok(
  (select sum(weight) from qb_season_builder_private.season_model_formulas where formula = 'score') > 0,
  'with weights that mean something'
);
select ok(
  not exists (
    select 1 from unnest(array['mvp', 'opoy', 'all_pro', 'pro_bowl', 'sb_mvp']) a(award)
     where not exists (select 1 from qb_season_builder_private.season_model_formulas f
                        where f.formula = 'award_' || a.award)
  ),
  'every award has a score to be judged on'
);
select ok(
  not exists (
    select 1 from qb_season_builder_private.season_model_formulas f
     where (f.formula in ('stat_line', 'team_success') or f.formula like 'award\_%')
       and not exists (select 1 from qb_season_builder_private.season_model_metrics m
                        where m.metric = f.term)
  ),
  'and every term of them is a metric with a real mean and spread to measure against'
);

-- ------------------------------------------------ in step with the finished ratings --

select cmp_ok(
  (select count(*)::int from qb_season_builder_private.season_model_real_seasons), '>=', 700,
  'every real quarterback-season is there, hundreds of them'
);
select is(
  (select count(*)::int from qb_season_builder_private.season_model_real_seasons),
  (select count(*)::int from qb_season_builder_private.qb_seasons),
  'exactly the ones the ratings rate'
);
select is(
  (select count(*)::int
     from qb_season_builder_private.season_model_real_seasons r
     join qb_season_builder_private.qb_seasons q using (franchise_code, season, player_id)
     join qb_season_builder_private.team_seasons t using (franchise_code, season)
    where (r.accuracy, r.arm_talent, r.mobility, r.iq, r.build, r.supporting_cast)
        = (q.accuracy, q.arm_talent, q.mobility, q.iq, q.build, t.supporting_cast)),
  (select count(*)::int from qb_season_builder_private.season_model_real_seasons),
  'each with the six values the game deals, so the closest real season is measured on what a player picked'
);
select ok(
  not exists (
    select 1 from qb_season_builder_private.season_model_real_seasons
     where wins + losses + ties not in (16, 17)
  ),
  'and the real record of a full regular season each'
);
select cmp_ok(
  (select count(*)::int from qb_season_builder_private.season_model_real_seasons where mvp), '>=', 10,
  'the real award winners are marked on their seasons'
);
select ok(
  not exists (
    select 1 from qb_season_builder_private.season_model_real_seasons
     group by season having count(*) filter (where mvp) > 1 or count(*) filter (where all_pro) > 1
  ),
  'never two MVPs or two first-team All-Pro quarterbacks in one year'
);

-- ------------------------------------------------ usable, extrapolating, bounded --

-- The fitted formula for an output at six values, the way season generation will
-- evaluate it: intercept plus coefficients times values, then the inverse link.
create function tests.expected(p_output text, p_value double precision)
returns double precision language sql stable as $$
  select case o.link
           when 'identity' then least(greatest(z.z, o.low), o.high)
           when 'log'      then least(exp(z.z), o.high)
           else o.low + (o.high - o.low) / (1 + exp(-z.z))
         end
    from qb_season_builder_private.season_model_outputs o,
         lateral (select o.intercept + coalesce(sum(c.coefficient * p_value), 0) as z
                    from qb_season_builder_private.season_model_coefficients c
                   where c.output = o.output) z
   where o.output = p_output
$$;

select ok(
  tests.expected('wins', 99) between 0 and 17 and tests.expected('wins', -500) between 0 and 17
  and tests.expected('wins', 5000) between 0 and 17,
  'wins never leave a 17 game season however far the values go'
);
select ok(
  tests.expected('wins', 99) > tests.expected('wins', 25),
  'a better build is expected to win more'
);
select ok(
  tests.expected('td_rate', -500) > 0 and tests.expected('int_rate', -500) > 0
  and tests.expected('td_rate', 5000) <= (select high from qb_season_builder_private.season_model_outputs
                                           where output = 'td_rate'),
  'and a rate can be neither negative nor past what the game allows'
);
select ok(
  tests.expected('ypa', 99) > tests.expected('ypa', 25)
  and tests.expected('comp_pct', 99) > tests.expected('comp_pct', 25),
  'and to throw better'
);

-- ---------------------------------------------------------- the schema holds the contract --

select throws_ok(
  $$ insert into qb_season_builder_private.season_model_coefficients (output, slot, coefficient)
     values ('wins', 'charisma', 1) $$,
  '23514', null, 'a coefficient must be for one of the six slots');
select throws_ok(
  $$ insert into qb_season_builder_private.season_model_coefficients (output, slot, coefficient)
     values ('sacks', 'accuracy', 1) $$,
  '23503', null, 'and an output the model knows');
select throws_ok(
  $$ insert into qb_season_builder_private.season_model_residuals (output, p, residual)
     values ('wins', 1.5, 0) $$,
  '23514', null, 'a residual quantile must be a probability');
select throws_ok(
  $$ update qb_season_builder_private.season_model_playoff_ladder set slope = -0.1 where rung = 1 $$,
  '23514', null, 'more wins is never a worse chance at a playoff rung');
select throws_ok(
  $$ update qb_season_builder_private.season_model_metrics set sd = 0 where metric = 'wins' $$,
  '23514', null, 'a metric cannot have no spread, which would divide by zero');
select throws_ok(
  $$ update qb_season_builder_private.season_model_outputs set link = 'probit' where output = 'wins' $$,
  '23514', null, 'a link is one of the three the formulas know');

-- ------------------------------------------------------------------ private --

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok('select count(*) from qb_season_builder_private.season_model_outputs',
  '42501', null, 'a signed-in player cannot read the fitted formulas');
select throws_ok('select count(*) from qb_season_builder_private.season_model_awards',
  '42501', null, 'nor the award thresholds');
select throws_ok('select count(*) from qb_season_builder_private.season_model_real_seasons',
  '42501', null, 'nor the real seasons');

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok('select count(*) from qb_season_builder_private.season_model_outputs',
  '42501', null, 'a guest cannot read the fitted formulas');
select throws_ok('select count(*) from qb_season_builder_private.season_model_playoff_ladder',
  '42501', null, 'nor the playoff ladder');

set local role anon;
select throws_ok('select count(*) from qb_season_builder_private.season_model_outputs',
  '42501', null, 'a signed-out client cannot read the fitted formulas');
select throws_ok('select count(*) from qb_season_builder_private.season_model_distributions',
  '42501', null, 'nor the score distributions');

select tests.act_as_admin();
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'qb_season_builder_private' and table_name like 'season\_model\_%'
       and grantee in ('anon', 'authenticated', 'PUBLIC', 'service_role')
  ),
  'no client role holds a privilege on any season model table'
);
select is(
  (select count(*)::int from pg_class
    where relnamespace = 'qb_season_builder_private'::regnamespace
      and relname like 'season\_model\_%' and relkind = 'r' and not relrowsecurity),
  0,
  'and row level security is on for every one of them as a second lock'
);

select * from finish();
rollback;
