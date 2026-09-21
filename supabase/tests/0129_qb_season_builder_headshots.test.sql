-- QB Season Builder publishes a dealt quarterback's portrait, never the pool.

begin;
select plan(3);

\ir support/harness.psql

insert into tests.fx (k, v) values ('a', tests.mkuser('ava'));
select tests.act_as_admin();
select tests.qsb_fixtures();

insert into tests.fx (k, v)
select 'visible', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.qsb_set_spin((select v from tests.fx where k = 'visible'), 1::smallint, 'phi', 2017::smallint);

select tests.act_as((select v from tests.fx where k = 'a'));
select is(
  (select options -> 'quarterbacks' -> 1 ->> 'headshot_url'
     from qb_season_builder.state((select v from tests.fx where k = 'visible'))),
  'https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66',
  'a dealt quarterback includes their headshot URL'
);

insert into tests.fx (k, v)
select 'hidden', tests.qsb_start((select v from tests.fx where k = 'a'), 'hidden');
select tests.qsb_set_spin((select v from tests.fx where k = 'hidden'), 1::smallint, 'phi', 2017::smallint);
select is(
  (select options -> 'quarterbacks' -> 1 ->> 'headshot_url'
     from qb_season_builder.state((select v from tests.fx where k = 'hidden'))),
  'https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66',
  'hidden mode conceals ratings, not a quarterback already shown to the player'
);

select is(
  (select picks -> 0 ->> 'headshot_url'
     from qb_season_builder.pick((select v from tests.fx where k = 'visible'), 'accuracy', 'WentCa00')),
  'https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vuolixdvigc8axelug66',
  'a picked quarterback keeps the portrait from their dealt spin'
);

select * from finish();
rollback;
