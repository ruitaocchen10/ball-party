begin;
select plan(5);

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

select * from finish();
rollback;
