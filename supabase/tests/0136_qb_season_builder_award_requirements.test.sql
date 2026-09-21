-- Tests for QB Season Builder's award hierarchy: an award can require another, so a
-- season is never given an MVP without the All-Pro or an All-Pro without the Pro Bowl.
-- Migration 0136.
--
-- Uses the small season model of tests.qsb_model_fixtures, whose every number can be
-- worked out by hand, and calls the pure generator directly. In that model
--
--   wins        0.2 x supporting_cast, capped at 17, and the MVP is judged on the
--               z-score of wins ((wins - 8) / 3) against a threshold of 1.5;
--   pass yards  (200 + 2 x accuracy) x (2 + 0.1 x arm_talent), and the All-Pro and Pro
--               Bowl are judged on the z-score of pass yards ((yards - 3000) / 1000)
--               against thresholds of 1.0 and 0.0.
--
-- so a build with a perfect cast and no arm or accuracy is an MVP by its own score and
-- fails the other two, and a build with a perfect arm and accuracy is the reverse. The
-- fixture's playoff ladder is cleared every time, so every season is a champion and the
-- Super Bowl MVP (yards z of 1.0 or more, and not tied to the other awards) follows yards.

begin;
select plan(11);

\ir support/harness.psql

select tests.act_as_admin();
select tests.qsb_model_fixtures();

-- A perfect cast and nothing else: 17 wins (z 3.0) and 400 yards (z -2.6).
select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":0,"arm_talent":0,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', 1)
     -> 'awards'),
  '{"mvp": true, "opoy": false, "all_pro": false, "pro_bowl": false, "sb_mvp": false}'::jsonb,
  'with no requirements each award is judged on its own score: a 17-win team with no offence is an MVP'
);

update qb_season_builder_private.season_model_awards set requires = 'all_pro' where award = 'mvp';

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":0,"arm_talent":0,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', 1)
     -> 'awards' ->> 'mvp')::boolean,
  false,
  'once the MVP requires the All-Pro, the same season is no longer an MVP'
);

-- A perfect arm and accuracy: 4,736 yards (z 1.7) but a cast of 0, so 0 wins (z -2.7).
select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":99,"arm_talent":99,"mobility":50,"iq":50,"build":50,"supporting_cast":0}', 1)
     -> 'awards'),
  '{"mvp": false, "opoy": true, "all_pro": true, "pro_bowl": true, "sb_mvp": true}'::jsonb,
  'the requirement only takes awards away: a great passer on a bad team is still All-Pro, and no MVP'
);

-- Both at once: 17 wins and 4,736 yards.
select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":99,"arm_talent":99,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', 1)
     -> 'awards' ->> 'mvp')::boolean,
  true,
  'a season that earns the All-Pro keeps the MVP its own score reaches'
);

-- A chain: the MVP needs the All-Pro, which needs the Pro Bowl. Move the Pro Bowl out
-- of reach and neither of the others can be earned however good their own scores.
update qb_season_builder_private.season_model_awards set requires = 'pro_bowl' where award = 'all_pro';
update qb_season_builder_private.season_model_awards set threshold = 1e9 where award = 'pro_bowl';

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":99,"arm_talent":99,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', 1)
     -> 'awards'),
  '{"mvp": false, "opoy": true, "all_pro": false, "pro_bowl": false, "sb_mvp": true}'::jsonb,
  'the requirements chain: no Pro Bowl means no All-Pro and so no MVP, while an unrelated award is untouched'
);

update qb_season_builder_private.season_model_awards set threshold = 0.0 where award = 'pro_bowl';

select is(
  (qb_season_builder_private.generate_season(
     '{"accuracy":99,"arm_talent":99,"mobility":50,"iq":50,"build":50,"supporting_cast":99}', 1)
     -> 'awards'),
  '{"mvp": true, "opoy": true, "all_pro": true, "pro_bowl": true, "sb_mvp": true}'::jsonb,
  'and with the Pro Bowl back within reach the whole chain is earned'
);

-- Whatever the build and seed, a season never has an award without the one it requires.
select tests.qsb_model_fixtures(1.0, 1.0, 5.0);   -- noise everywhere, so awards are coin flips
update qb_season_builder_private.season_model_awards set requires = 'all_pro' where award = 'mvp';
update qb_season_builder_private.season_model_awards set requires = 'pro_bowl' where award in ('all_pro', 'opoy');

create temp table hier on commit drop as
select a.j -> 'awards' as awards
  from (
    select qb_season_builder_private.generate_season(
             jsonb_build_object('accuracy', (s * 7) % 100, 'arm_talent', (s * 13) % 100,
                                'mobility', 50, 'iq', 50, 'build', 50,
                                'supporting_cast', (s * 29) % 100),
             s) as j
      from generate_series(1, 400) s
  ) a;

select is(
  (select count(*) from hier where (awards ->> 'mvp')::boolean and not (awards ->> 'all_pro')::boolean),
  0::bigint, 'over 400 noisy seasons no MVP is without the All-Pro'
);
select is(
  (select count(*) from hier where (awards ->> 'all_pro')::boolean and not (awards ->> 'pro_bowl')::boolean),
  0::bigint, 'no All-Pro is without the Pro Bowl'
);
select is(
  (select count(*) from hier where (awards ->> 'opoy')::boolean and not (awards ->> 'pro_bowl')::boolean),
  0::bigint, 'no Offensive Player of the Year is without the Pro Bowl'
);
select cmp_ok(
  (select count(*) from hier where (awards ->> 'mvp')::boolean), '>', 0::bigint,
  'and the noise still hands out some MVPs, so the checks above are not vacuous'
);

select throws_ok(
  $$ update qb_season_builder_private.season_model_awards set requires = 'heisman' where award = 'mvp' $$,
  '23514', null,
  'an award can only require one of the five awards'
);

select * from finish();
rollback;
