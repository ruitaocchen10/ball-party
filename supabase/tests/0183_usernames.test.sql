begin;
select plan(28);

\ir support/harness.psql

insert into tests.fx (k, v) values
  ('zed',    tests.mkuser('Zed Quill')),
  ('zed2',   tests.mkuser('Zed Quill')),
  ('weird',  tests.mkuser('Ma!!')),
  ('guest',  tests.mkguest('Visitor')),
  ('other',  tests.mkuser('Other Person'));

-- ------------------------------------------------------------- derivation --

select is(
  (select username from public.profiles where id = (select v from tests.fx where k = 'zed')),
  'Zed_Quill',
  'a new account gets a username derived from its display name'
);
select is(
  (select username from public.profiles where id = (select v from tests.fx where k = 'zed2')),
  'Zed_Quill2',
  'a collision gets a numeric suffix'
);
select is(private.derive_username_base('Ma!!'), 'Ma_', 'a too-short base is padded to the 3-character minimum');
select is(private.derive_username_base('日本語'), 'player', 'a name with nothing usable falls back to "player"');
select is(private.derive_username_base(repeat('a', 40)), repeat('a', 20), 'a long base is cut to 20 characters');
select is(
  (select username from public.profiles where id = (select v from tests.fx where k = 'guest')),
  null,
  'a guest has no username'
);

-- A guest who upgrades becomes a real account and is given one.
update auth.users set is_anonymous = false where id = (select v from tests.fx where k = 'guest');
select is(
  (select username from public.profiles where id = (select v from tests.fx where k = 'guest')),
  'Visitor',
  'an upgraded guest is assigned a username'
);

-- ------------------------------------------------------------------ claim --

select tests.act_as((select v from tests.fx where k = 'zed'));

select is(public.claim_username('QuillMaster'), 'QuillMaster', 'claim_username returns the stored name');
select is(
  (select username from public.profiles where id = (select v from tests.fx where k = 'zed')),
  'QuillMaster',
  'the claimed name is stored as typed'
);
select is(public.claim_username('quillmaster'), 'quillmaster', 'a player can re-case their own name');

select tests.act_as((select v from tests.fx where k = 'other'));
select throws_ok(
  $$ select public.claim_username('QuillMaster') $$,
  '23505', 'username_taken',
  'a name taken by someone else (ignoring case) is refused'
);
select throws_ok($$ select public.claim_username('ab') $$, '22023', 'invalid_username', 'too short is refused');
select throws_ok($$ select public.claim_username('has space') $$, '22023', 'invalid_username', 'spaces are refused');
select throws_ok($$ select public.claim_username('dash-ed') $$, '22023', 'invalid_username', 'punctuation other than underscore is refused');
select throws_ok($$ select public.claim_username('aaaaaaaaaaaaaaaaaaaaa') $$, '22023', 'invalid_username', 'more than 20 characters is refused');
select throws_ok($$ select public.claim_username(null) $$, '22023', 'invalid_username', 'null is refused');
select throws_ok($$ select public.claim_username('Admin') $$, '22023', 'username_reserved', 'a reserved name is refused');

-- ------------------------------------------------------------ availability --

select is(public.username_available('FreshName'), true, 'an unused valid name is available');
select is(public.username_available('quillmaster'), false, 'a taken name is unavailable, ignoring case');
select is(public.username_available('Other_Person'), true, 'a player''s own current name counts as available to them');
select is(public.username_available('ab'), false, 'an invalid name is unavailable');
select is(public.username_available('admin'), false, 'a reserved name is unavailable');

-- ------------------------------------------------------------ guests / auth --

select tests.act_as_admin();
select tests.mkguest('Second Visitor') as g \gset
select tests.act_as_guest(:'g');
select throws_ok(
  $$ select public.claim_username('GuestTry') $$,
  '42501', 'guests_cannot_have_username',
  'a guest cannot claim a username'
);

-- ------------------------------------------------------------ direct writes --

select tests.act_as((select v from tests.fx where k = 'other'));
select throws_ok(
  $$ update public.profiles set username = 'Hacked' where id = auth.uid() $$,
  '42501', null,
  'a username cannot be written around claim_username'
);
select lives_ok(
  $$ update public.profiles set display_name = 'Renamed' where id = auth.uid() $$,
  'display_name is still directly editable'
);

-- ------------------------------------------------------------- rate limits --

select tests.act_as((select v from tests.fx where k = 'zed2'));
select lives_ok(
  $$ select public.claim_username('Rate' || n) from generate_series(1, 10) n $$,
  'ten name changes in an hour are allowed'
);
select throws_ok(
  $$ select public.claim_username('RateEleven') $$,
  '54000', 'rate_limited',
  'the eleventh change in an hour is refused'
);

-- ---------------------------------------------------------------- deletion --

select tests.act_as((select v from tests.fx where k = 'other'));
select public.delete_own_account();
select tests.act_as_admin();
select is(
  (select username from public.profiles where id = (select v from tests.fx where k = 'other')),
  null,
  'deleting an account releases its username'
);

select * from finish();
rollback;
