begin;
select plan(8);

\ir support/harness.psql

insert into tests.fx (k, v) values
  ('ana',   tests.mkuser('Ana Private')),
  ('guest', tests.mkguest('Visiting'));

select tests.act_as((select v from tests.fx where k = 'ana'));

select is(
  (select is_private from public.profiles where id = (select v from tests.fx where k = 'ana')),
  false,
  'profiles are public by default'
);
select is(public.set_profile_private(true), true, 'set_profile_private returns the new value');
select is(
  (select is_private from public.profiles where id = (select v from tests.fx where k = 'ana')),
  true,
  'the flag is stored'
);
select is(public.set_profile_private(false), false, 'a profile can go public again');
select throws_ok($$ select public.set_profile_private(null) $$, '22023', 'invalid_value', 'null is refused');
select throws_ok(
  $$ update public.profiles set is_private = true where id = auth.uid() $$,
  '42501', null,
  'the flag cannot be written around the RPC'
);

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok(
  $$ select public.set_profile_private(true) $$,
  '42501', 'guests_cannot_set_privacy',
  'a guest cannot set privacy'
);

select tests.act_as_admin();
select is(
  (select is_private from public.profiles where id = (select v from tests.fx where k = 'guest')),
  false,
  'a refused call leaves the guest unchanged'
);

select * from finish();
rollback;
