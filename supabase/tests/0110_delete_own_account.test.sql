begin;
select plan(7);

\ir support/harness.psql

insert into tests.fx (k, v) values
  ('a', tests.mkuser('Ava')),
  ('b', tests.mkuser('Bo'));

select tests.act_as((select v from tests.fx where k = 'a'));

select lives_ok(
  'select public.delete_own_account()',
  'a signed-in player can anonymize their own profile'
);

select is(
  (select display_name from public.profiles where id = (select v from tests.fx where k = 'a')),
  'Deleted player',
  'the caller''s display name is anonymized'
);
select is(
  (select rankings_visible from public.profiles where id = (select v from tests.fx where k = 'a')),
  false,
  'the caller drops out of the rankings cohort'
);
select isnt(
  (select deleted_at from public.profiles where id = (select v from tests.fx where k = 'a')),
  null,
  'deleted_at is stamped'
);

-- Ava and Bo were never co-players, so profiles_select_co_player would hide
-- this row from her anyway — check as admin to isolate what the RPC did.
select tests.act_as_admin();
select is(
  (select display_name from public.profiles where id = (select v from tests.fx where k = 'b')),
  'Bo',
  'another player''s profile is untouched'
);

-- Sign-in is blocked for the caller only. GoTrue refuses a banned user, so this
-- is what actually stops the old credentials from working.
select ok(
  (select banned_until > now() + interval '50 years' from auth.users where id = (select v from tests.fx where k = 'a')),
  'the caller is banned from signing in'
);
select is(
  (select banned_until from auth.users where id = (select v from tests.fx where k = 'b')),
  null,
  'another player can still sign in'
);

select * from finish();
rollback;
