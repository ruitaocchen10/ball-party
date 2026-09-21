-- Tests for QB Season Builder's playoff-ladder guarantees: a rung can be always cleared from
-- some number of wins and never cleared at or below another, whatever the draw says.
-- Migration 0139 (the shipped guarantees themselves arrive with the data in 0140).
--
-- Uses the small season model of tests.qsb_model_fixtures, in which wins are exactly
-- 0.2 x supporting_cast (capped at 17): a cast of 99 is 17 wins, 60 is 12, 55 is 11, 30 is 6
-- and 25 is 5. The fixture's playoff ladder is one number for every rung (slope 0): -50 misses
-- the first rung every time, +50 clears every rung, 0 is a coin flip.

begin;
select plan(11);

\ir support/harness.psql

select tests.act_as_admin();

-- The model in force, before the fixtures replace it: the data migration turns the
-- guarantee on for the first rung, and only there is one needed.
select ok(
  exists (select 1 from qb_season_builder_private.season_model_playoff_ladder
           where step = 'make_playoffs' and always_from is not null and never_to is not null),
  'the shipped model guarantees both ends of the make-the-playoffs rung'
);

-- ------------------------------------------- a ladder nobody clears (-50) --

select tests.qsb_model_fixtures(0, 0, 0, -50);

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', 1)
     #>> '{playoffs,result}'),
  'missed_playoffs',
  'without a guarantee a 17-win team misses the playoffs when the draw says so'
);

update qb_season_builder_private.season_model_playoff_ladder set always_from = 12 where step = 'make_playoffs';

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', 1)
     #>> '{playoffs,result}'),
  'lost_wild_card',
  'with the guarantee the same team makes it, and the later rungs (still -50) are the draw''s'
);

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":60}', 1)
     #>> '{playoffs,depth}')::int,
  1,
  'a team with exactly the guaranteed wins (12) is in'
);

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":55}', 1)
     #>> '{playoffs,depth}')::int,
  0,
  'and one win fewer (11) is left to the draw'
);

-- ----------------------------------------- a ladder everybody clears (+50) --

select tests.qsb_model_fixtures(0, 0, 0, 50);

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":25}', 1)
     #>> '{playoffs,result}'),
  'won_super_bowl',
  'without a guarantee a 5-12 team wins the title when the draw says so'
);

update qb_season_builder_private.season_model_playoff_ladder set never_to = 5 where step = 'make_playoffs';

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":25}', 1)
     #>> '{playoffs,result}'),
  'missed_playoffs',
  'with the guarantee a team with exactly the wins it never clears on (5) misses'
);

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":30}', 1)
     #>> '{playoffs,result}'),
  'won_super_bowl',
  'and one win more (6) is left to the draw'
);

-- -------------------------------- across many seeds, on a coin-flip ladder --

select tests.qsb_model_fixtures(0, 0, 0, 0);

create temp table without_guarantee on commit drop as
select (qb_season_builder_private.generate_season(
          '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', s)
          #>> '{playoffs,depth}')::int as depth
  from generate_series(1, 200) s;

update qb_season_builder_private.season_model_playoff_ladder set always_from = 12 where step = 'make_playoffs';

create temp table with_guarantee on commit drop as
select (qb_season_builder_private.generate_season(
          '{"accuracy":50,"arm_talent":50,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', s)
          #>> '{playoffs,depth}')::int as depth
  from generate_series(1, 200) s;

select cmp_ok(
  (select count(*) from without_guarantee where depth = 0), '>', 0::bigint,
  'over 200 seeds a coin-flip rung does turn some 17-win teams away, so the next check is not vacuous'
);
select is(
  (select count(*) from with_guarantee where depth = 0), 0::bigint,
  'and with the guarantee not one 17-win team misses'
);

-- ------------------------------------------------------------- the checks --

select throws_ok(
  $$ update qb_season_builder_private.season_model_playoff_ladder set never_to = 12
      where step = 'make_playoffs' $$,
  '23514', null,
  'a rung cannot never be cleared at wins where it is always cleared'
);

select * from finish();
rollback;
