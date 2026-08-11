-- The collision breadcrumb's authorisation, which is the whole point of the
-- table: it exists to authorise a future reattachment of match history, so a
-- row anyone can write is worse than no row at all.
--
-- These assert what a caller can and cannot cause, never which branch rejected
-- them. The one exception is the deliberate conflation of unknown, redeemed,
-- and expired into a single error, which is itself the behaviour under test.

begin;
select plan(9);

\ir support/harness.psql

insert into tests.fx (k, v) values ('guest',   tests.mkguest('Devin'));
insert into tests.fx (k, v) values ('other',   tests.mkguest('Rowan'));
insert into tests.fx (k, v) values ('account', tests.mkuser('Morgan'));
insert into tests.fx (k, v) values ('bystander', tests.mkuser('Sam'));

-- ------------------------------------------------------------- staking --

select tests.act_as((select v from tests.fx where k = 'account'));
select throws_ok(
  'select public.claim_guest_identity()',
  '42501', 'not_a_guest',
  'a credentialed account cannot stake a guest claim'
);

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
insert into tests.fx (k, v) select 'nonce', public.claim_guest_identity();
select isnt(
  (select v from tests.fx where k = 'nonce'), null,
  'a guest receives a nonce for its own identity'
);

-- ------------------------------------------------------------ redeeming --

-- The old version took a guest id and would accept any guest a caller named.
-- A bystander now has nothing to offer but a guess at the nonce.
select tests.act_as((select v from tests.fx where k = 'bystander'));
select throws_ok(
  format($$ select public.record_guest_account_collision(%L) $$, gen_random_uuid()),
  'P0001', 'claim_not_found',
  'a bystander cannot claim a guest it never was'
);

select tests.act_as_admin();
select is(
  (select account_id from public.guest_account_collisions
    where guest_id = (select v from tests.fx where k = 'guest')),
  null,
  'a failed redemption leaves the claim open'
);

select tests.act_as((select v from tests.fx where k = 'account'));
select lives_ok(
  format($$ select public.record_guest_account_collision(%L) $$, (select v from tests.fx where k = 'nonce')),
  'the holder of the nonce settles the breadcrumb'
);

select throws_ok(
  format($$ select public.record_guest_account_collision(%L) $$, (select v from tests.fx where k = 'nonce')),
  'P0001', 'claim_not_found',
  'a nonce is single use'
);

-- ------------------------------------------------------------ immutable --

-- The old upsert let a later caller overwrite a settled breadcrumb, which is
-- how a legitimate claim could be stolen rather than merely invented.
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok(
  'select public.claim_guest_identity()',
  'P0001', 'already_settled',
  'a settled breadcrumb cannot be re-opened'
);

select tests.act_as_admin();
select is(
  (select account_id from public.guest_account_collisions
    where guest_id = (select v from tests.fx where k = 'guest')),
  (select v from tests.fx where k = 'account'),
  'the settled breadcrumb still names the account that redeemed it'
);

-- -------------------------------------------------------------- expiry --

select tests.act_as_guest((select v from tests.fx where k = 'other'));
insert into tests.fx (k, v) select 'stale', public.claim_guest_identity();
select tests.act_as_admin();
update public.guest_account_collisions
   set created_at = now() - interval '2 hours'
 where guest_id = (select v from tests.fx where k = 'other');

select tests.act_as((select v from tests.fx where k = 'bystander'));
select throws_ok(
  format($$ select public.record_guest_account_collision(%L) $$, (select v from tests.fx where k = 'stale')),
  'P0001', 'claim_not_found',
  'an expired claim cannot be redeemed'
);

select * from finish();
rollback;
