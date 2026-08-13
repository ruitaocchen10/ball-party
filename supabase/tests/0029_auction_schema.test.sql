-- The auction's schema boundary.
--
-- 0004 made `private` unreachable and 0010 asserted that the answers never
-- leave it. This suite asserts the same property for the split introduced in
-- 0029: `auction` is API surface and `auction_private` is not, and the way a
-- future migration would break that is by widening a grant rather than by
-- changing a screen. So the assertions are about privileges and catalogs.
begin;
select plan(12);

\ir support/harness.psql

-- --------------------------------------------------------------- the schemas --

select ok(
  has_schema_privilege('authenticated', 'auction', 'usage'),
  'a participant can reach the auction schema, since that is the write API'
);

select ok(
  not has_schema_privilege('authenticated', 'auction_private', 'usage'),
  'but not the engine schema — the same shape private has had since 0004'
);

select ok(
  not has_schema_privilege('anon', 'auction_private', 'usage'),
  'and anon cannot either'
);

-- ------------------------------------------------------------ the write API --

select bag_eq(
  $$ select p.proname::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'auction' $$,
  $$ values ('start'), ('state'), ('place_bid'), ('pass_lot'), ('expire_turn') $$,
  'the exposed schema holds exactly the five functions a client may call'
);

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auction'),
  'and a participant may execute all of them'
);

select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auction'),
  'while anon may execute none of them — guests sign in before they play'
);

-- ---------------------------------------------------------------- the engine --

select ok(
  (select bool_and(not has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auction_private'),
  'no engine function is executable by a participant'
);

select ok(
  (select count(*) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auction_private'),
  'and that assertion is not vacuous — the engine schema is populated'
);

-- ------------------------------------------------------- nothing left behind --

select is_empty(
  $$ select n.nspname::text || '.' || p.proname::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and (p.proname like '%auction%' or p.proname in ('place_bid', 'pass_lot', 'expire_turn')) $$,
  'no auction function is left in public or private'
);

-- The hidden-state tables deliberately stayed in `private` — 0029 moved
-- functions only. If they ever move, 0010's leak assertions move with them.
select has_table('private', 'auction_answers',
  'the answers table is still where the leak test looks for it');

-- ----------------------------------------------------------------- it still runs --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('match', tests.deal_and_open(4, .5));

select isnt_empty(
  $$ select 1 from public.auction_lots
      where match_id = (select v from tests.fx where k = 'match') $$,
  'a board still deals through the relocated dealer'
);

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'match')));

select throws_ok(
  format(
    'select auction_private.apply(%L::uuid, %L::uuid, ''pass'', null::numeric, false)',
    (select v from tests.fx where k = 'match'),
    tests.on_clock((select v from tests.fx where k = 'match'))
  ),
  '42501',
  null,
  'and the player on the clock still cannot call the engine directly to bypass a rule'
);

select * from finish();
rollback;
