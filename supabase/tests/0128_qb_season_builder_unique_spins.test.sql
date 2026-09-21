-- QB Season Builder spins are unique for a run, including a respun-away spin.

begin;
select plan(2);

\ir support/harness.psql

insert into tests.fx (k, v) values ('a', tests.mkuser('ava'));

select tests.act_as_admin();
select tests.qsb_fixtures();

insert into tests.fx (k, v)
select 'm', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 1::smallint, 'phi', 2017::smallint);

-- The respin cannot return the original spin, then the next round cannot
-- return either spin the player has already seen.
select tests.act_as((select v from tests.fx where k = 'a'));
select qb_season_builder.respin((select v from tests.fx where k = 'm'));
select qb_season_builder.pick(
  (select v from tests.fx where k = 'm'),
  'accuracy',
  (select options -> 'quarterbacks' -> 0 ->> 'player_id'
     from qb_season_builder.state((select v from tests.fx where k = 'm')))
);

select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm')),
  (select count(distinct (franchise_code, season))::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm')),
  'every shown team-season is unique, including the replaced spin'
);
select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm')),
  3,
  'the comparison includes the original spin, respin, and next-round spin'
);

select * from finish();
rollback;
