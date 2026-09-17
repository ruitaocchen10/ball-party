begin;
select plan(2);

\ir support/harness.psql

insert into tests.fx (k, v) values ('player', tests.mkuser('Ava'));

select tests.act_as((select v from tests.fx where k = 'player'));
select lives_ok(
  format($$ update public.profiles set display_name = 'Avery' where id = %L $$, (select v from tests.fx where k = 'player')),
  'an authenticated player can update their own profile'
);

select is(
  (select display_name from public.profiles where id = (select v from tests.fx where k = 'player')),
  'Avery',
  'the profile update persists within the authenticated session'
);

select * from finish();
rollback;
