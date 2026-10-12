-- Tests for device tokens (0205): register, refresh, move between accounts,
-- unregister, guests, and that clients cannot touch the table directly.

begin;
select plan(15);
\ir support/harness.psql

insert into tests.fx (k, v) values
  ('alice', tests.mkuser('DtAlice')),
  ('bob',   tests.mkuser('DtBob')),
  ('guest', tests.mkguest('DtGuest'));

create function tests.who(p_k text) returns uuid language sql stable as $$ select v from tests.fx where k = p_k $$;

select tests.act_as(tests.who('alice'));
select public.register_device_token(repeat('a', 64), 'sandbox');
select tests.act_as_admin();
select is((select count(*)::integer from public.device_tokens where user_id = tests.who('alice')), 1, 'registering stores the token for the caller');
select is((select environment from public.device_tokens where token = repeat('a', 64)), 'sandbox', 'with its APNs environment');
select is((select platform from public.device_tokens where token = repeat('a', 64)), 'ios', 'and the platform defaults to ios');

-- Registering again is a refresh, not a second row.
update public.device_tokens set last_seen = now() - interval '2 days';
select tests.act_as(tests.who('alice'));
select public.register_device_token(repeat('a', 64), 'sandbox');
select tests.act_as_admin();
select is((select count(*)::integer from public.device_tokens), 1, 'registering the same token again keeps one row');
select ok((select last_seen > now() - interval '1 minute' from public.device_tokens), 'and refreshes last_seen');

-- The same token in the other environment is a different registration.
select tests.act_as(tests.who('alice'));
select public.register_device_token(repeat('a', 64), 'production');
select tests.act_as_admin();
select is((select count(*)::integer from public.device_tokens), 2, 'the same token in another environment is its own row');

-- A new account signing in on the device takes the token over.
select tests.act_as(tests.who('bob'));
select public.register_device_token(repeat('a', 64), 'sandbox');
select tests.act_as_admin();
select is((select user_id from public.device_tokens where token = repeat('a', 64) and environment = 'sandbox'), tests.who('bob'),
  'registering a token from another account moves it');
select is((select count(*)::integer from public.device_tokens where user_id = tests.who('alice') and environment = 'sandbox'), 0,
  'so the previous account no longer receives pushes on it');

-- Unregister only removes the caller's own row.
select tests.act_as(tests.who('alice'));
select is(public.unregister_device_token(repeat('a', 64)), true, 'unregister removes the caller''s token');
select is(public.unregister_device_token(repeat('a', 64)), false, 'a second unregister changes nothing');
select tests.act_as(tests.who('bob'));
select public.register_device_token(repeat('b', 64), 'sandbox');
select tests.act_as(tests.who('alice'));
select is(public.unregister_device_token(repeat('b', 64)), false, 'unregister cannot remove another account''s token');

-- Access.
select throws_ok($$ select public.register_device_token('short', 'sandbox') $$, '23514', null, 'a malformed token is refused');
select tests.act_as_guest(tests.who('guest'));
select throws_ok($$ select public.register_device_token(repeat('c', 64), 'sandbox') $$, '28000', null, 'a guest cannot register a device');
select tests.act_as(tests.who('alice'));
select throws_ok($$ select * from public.device_tokens $$, '42501', null, 'clients cannot read the table');
select throws_ok($$ select public.delete_device_tokens(array[repeat('b', 64)]) $$, '42501', null, 'clients cannot call the sender''s cleanup');

select * from finish();
rollback;
