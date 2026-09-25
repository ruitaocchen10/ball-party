-- Tests for QB Season Builder's era presets (migration 0153). See the
-- migration's own header for why these presets carry no minimum span, unlike
-- the auction's free season_from/season_to (0030): draw_spin (0128) already
-- excludes every team-season a run has shown, across rounds and the respin
-- alike, whatever era it draws from.
--
-- tests.qsb_fixtures() gives the modern-era pool every other QB Season Builder
-- suite uses (kan2018, kan2019, nwe2017, phi2017 qualifying; nyj2020 never
-- spun). This file adds three classic-era team-seasons of its own, local to
-- this transaction, rather than touching the shared fixture every other suite
-- reads. Three, not two: a run in the loop below draws up to three times
-- (start, a pick's next round, a respin) and none may repeat, so the classic
-- pool needs at least that many to never spuriously exhaust.

begin;
select plan(11);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('stranger', tests.mkuser('sten'));

select tests.act_as_admin();
select tests.qsb_fixtures();

insert into qb_season_builder_private.team_seasons (franchise_code, season, supporting_cast)
values ('gnb', 2011, 92), ('den', 2012, 84), ('nor', 2009, 88);

insert into qb_season_builder_private.qb_seasons
  (franchise_code, season, player_id, display_name, accuracy, arm_talent, mobility, iq, build)
values
  ('gnb', 2011, 'RodgAa00', 'Aaron Rodgers', 94, 92, 62, 91, 74),
  ('den', 2012, 'MannPe00', 'Peyton Manning', 93, 78, 15, 97, 71),
  ('nor', 2009, 'BreeDr00', 'Drew Brees',     95, 84, 40, 90, 65);

-- ------------------------------------------------------------ choosing an era --

insert into tests.fx (k, v)
select 'default', tests.qsb_start((select v from tests.fx where k = 'a'));
select is(
  (select era from qb_season_builder.state((select v from tests.fx where k = 'default'))),
  'all',
  'era defaults to all when none is chosen'
);

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  $$ select qb_season_builder.start((select id from public.start_solo_run('qb_season_builder')), 'visible', 'ancient') $$,
  '22023', 'invalid_era',
  'an era other than all, classic or modern is refused'
);

-- ---------------------------------------------------------------- classic --

insert into tests.fx (k, v)
select 'classic', tests.qsb_start((select v from tests.fx where k = 'a'), 'visible', false, 'classic');
select is(
  (select era from qb_season_builder.state((select v from tests.fx where k = 'classic'))),
  'classic',
  'the chosen era is what state reads back'
);
select ok(
  (select franchise_code || season from qb_season_builder.state((select v from tests.fx where k = 'classic')))
    in ('gnb2011', 'den2012', 'nor2009'),
  'a classic run is dealt from 2006-2015 only'
);

-- ----------------------------------------------------------------- modern --

insert into tests.fx (k, v)
select 'modern', tests.qsb_start((select v from tests.fx where k = 'a'), 'visible', false, 'modern');
select ok(
  (select franchise_code || season from qb_season_builder.state((select v from tests.fx where k = 'modern')))
    in ('kan2018', 'kan2019', 'nwe2017', 'phi2017'),
  'a modern run never sees a classic team-season'
);

-- ------------------------------------------------------- every draw stays in it --

-- Thirty fresh classic runs, each drawn three times (the opening deal, the
-- next round's deal from a pick, and a respin) against a classic pool of
-- exactly three team-seasons: every draw is one of the three, and — since
-- draw_spin never repeats a team-season a run has already shown — the three
-- draws in one run are pairwise distinct with nothing left over.
do $$
declare
  v_user  uuid := tests.mkuser('classic-fan');
  v_match uuid;
  v_bad   int := 0;
  v_keys  text[];
begin
  for i in 1 .. 30 loop
    v_match := tests.qsb_start(v_user, 'visible', false, 'classic');
    select array[franchise_code || season] into v_keys from qb_season_builder.state(v_match);

    perform qb_season_builder.pick(v_match, 'accuracy',
      (select options -> 'quarterbacks' -> 0 ->> 'player_id' from qb_season_builder.state(v_match)));
    select v_keys || (franchise_code || season) into v_keys from qb_season_builder.state(v_match);

    perform qb_season_builder.respin(v_match);
    select v_keys || (franchise_code || season) into v_keys from qb_season_builder.state(v_match);

    if exists (
      select 1 from unnest(v_keys) k where k not in ('gnb2011', 'den2012', 'nor2009')
    ) then
      v_bad := v_bad + 1;
    end if;
    if cardinality(array(select distinct k from unnest(v_keys) k)) <> 3 then
      v_bad := v_bad + 1;
    end if;
  end loop;
  perform tests.act_as_admin();
  insert into tests.num (k, v) values ('classic_bad', v_bad);
end $$;

select tests.act_as_admin();
select is(
  (select v from tests.num where k = 'classic_bad'), 0,
  'the deal, a pick''s next round and a respin all stay inside the chosen era, never repeating'
);

-- ------------------------------------------------------------- era is locked --

select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select era from qb_season_builder.state((select v from tests.fx where k = 'classic'))),
  'classic',
  'era is unaffected by picks and respins made on other runs'
);
select throws_ok(
  format($$ select qb_season_builder.start(%L, 'visible', 'modern') $$, (select v from tests.fx where k = 'classic')),
  'P0001', 'match_not_setup',
  'a dealt run cannot be started again, so its era cannot be re-chosen either'
);

-- ----------------------------------------------------------------- guests --

insert into tests.fx (k, v)
values ('guest', tests.mkguest('gwen'));
insert into tests.fx (k, v)
select 'g', tests.qsb_start((select v from tests.fx where k = 'guest'), 'visible', true, 'modern');
select is(
  (select era from qb_season_builder.state((select v from tests.fx where k = 'g'))),
  'modern',
  'a guest can choose an era too'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select qb_season_builder.state(%L) $$, (select v from tests.fx where k = 'classic')),
  '42501', 'not_a_participant',
  'someone else still cannot read a run they are not in, era included'
);

-- ------------------------------------------------------------ pool_exhausted --

-- An era with nothing to deal from raises the same pool_exhausted the whole
-- pool already could — a pipeline-data problem, not a new failure mode. Cleared
-- last, since every assertion above needs the classic fixture in place.
select tests.act_as_admin();
delete from qb_season_builder_private.qb_seasons where franchise_code in ('gnb', 'den', 'nor');
delete from qb_season_builder_private.team_seasons where franchise_code in ('gnb', 'den', 'nor');

select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  $$ select qb_season_builder.start((select id from public.start_solo_run('qb_season_builder')), 'visible', 'classic') $$,
  'P0001', 'pool_exhausted',
  'an era with no qualifying team-season left is refused the same way an empty pool always was'
);

select * from finish();
rollback;
