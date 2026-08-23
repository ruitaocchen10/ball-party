-- Tests for the sabotage draft schema, its team spin, and its dealer
-- (migration 0051).
--
-- The composition tests assert the shape the design doc promises: fourteen
-- rounds, rounds 1-13 in the fixed slot order, round 14 the X-Factor. The
-- repeat test asserts the property the design doc calls out by name — a
-- franchise can be spun more than once across the fourteen rounds, because
-- nothing tracks an exclusion set.

begin;
select plan(38);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m4', tests.deal_sabotage_draft(4, 0.25));
select tests.act_as_admin();

-- ------------------------------------------------------------- composition --

select is(
  (select count(*)::int from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  14,
  'a dealt match holds fourteen rounds'
);

select is(
  (select array_agg(round_number order by round_number) from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  (select array_agg(g::smallint order by g) from generate_series(1, 14) g),
  'and their round numbers run 1..14 without a gap'
);

select is(
  (select array_agg(slot order by round_number) from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  array['QB','RB1','RB2','WR1','WR2','WR3','TE','OL','DL','LB','CB','S','ST','X_FACTOR'],
  'rounds 1-13 fill the fixed slot order the design doc lists, and round 14 is the X-Factor'
);

select ok(
  (select bool_and(franchise_code <> '') from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  'every round spins a real franchise'
);

select is(
  (select round_count::int from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm4')),
  14,
  'the match records the round count'
);

select is(
  (select current_round::int from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm4')),
  1,
  'a freshly dealt match starts on round one'
);

select is(
  (select array_agg(seat order by seat) from public.sabotage_draft_players
    where match_id = (select v from tests.fx where k = 'm4')),
  array[0, 1, 2, 3]::smallint[],
  'every seated player gets a row'
);

select ok(
  not exists (
    select 1
      from public.sabotage_draft_players sp
      join public.matches mt on mt.id = sp.match_id
      join public.run_participants rp on rp.run_id = mt.run_id and rp.user_id = sp.user_id
     where sp.match_id = (select v from tests.fx where k = 'm4')
       and sp.seat is distinct from rp.seat
  ),
  'and seats are copied from run_participants rather than shuffled again'
);

-- --------------------------------------------------------- the pool categories --

select is(
  sabotage_draft_private.pool_categories('QB'), array['QB'], 'QB maps to itself'
);
select is(
  sabotage_draft_private.pool_categories('RB1'), array['RB'], 'RB1 folds onto the RB category'
);
select is(
  sabotage_draft_private.pool_categories('RB2'), array['RB'], 'RB2 folds onto the same RB category'
);
select is(
  sabotage_draft_private.pool_categories('WR2'), array['WR'], 'WR2 folds onto the WR category'
);
select is(
  sabotage_draft_private.pool_categories('X_FACTOR'), array['QB','RB','WR','TE'],
  'the X-Factor is eligible across every skill category, not one fixed slot'
);
select throws_ok(
  $$ select sabotage_draft_private.pool_categories('QB1') $$,
  'P0001', 'unknown_slot',
  'a slot outside the fourteen named ones is refused rather than silently mapped'
);

-- Every dealt round's franchise really does have players at the category
-- (or, for the X-Factor, categories) its slot allows — the query the dealer
-- itself runs, asserted against the real pool rather than trusted.
select ok(
  not exists (
    select 1 from public.sabotage_draft_rounds r
     where r.match_id = (select v from tests.fx where k = 'm4')
       and not exists (
         select 1 from private.av_roster_players p
          where p.franchise_code = r.franchise_code
            and p.slot_category = any(sabotage_draft_private.pool_categories(r.slot))
       )
  ),
  'every spun franchise actually has players at the round''s eligible category'
);

-- ------------------------------------------------------------ the repeat --

-- The property the design doc names directly: no exclusion set, so a
-- franchise spun once can be spun again in a later round. Draws are
-- independent of player count, so this holds regardless of table size; a
-- fixed seed picked because it happens to produce one is enough to show the
-- mechanism allows it, which is the thing under test — a constraint that
-- forbade it would fail this rather than merely go untested.
select ok(
  (select count(*) > count(distinct franchise_code) from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  'this board actually repeats a franchise across rounds'
);

select ok(
  not exists (
    select 1 from pg_constraint
     where conrelid = 'public.sabotage_draft_rounds'::regclass
       and contype in ('u', 'x')
       and pg_get_constraintdef(oid) ilike '%franchise_code%'
  ),
  'and nothing in the schema stops it — no unique or exclusion constraint touches franchise_code'
);

-- ------------------------------------------------------ reproducibility --

insert into tests.fx (k, v) values ('m4_same',  tests.deal_sabotage_draft(4, 0.25));
insert into tests.fx (k, v) values ('m4_other', tests.deal_sabotage_draft(4, 0.9));
select tests.act_as_admin();

select is(
  (select array_agg(slot || ':' || franchise_code order by round_number)
     from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4_same')),
  (select array_agg(slot || ':' || franchise_code order by round_number)
     from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  'the same seed deals an identical board, round for round'
);

select isnt(
  (select array_agg(franchise_code order by round_number) from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4_other')),
  (select array_agg(franchise_code order by round_number) from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  'a different seed does not'
);

select is(
  (select seed from sabotage_draft_private.boards
    where match_id = (select v from tests.fx where k = 'm4')),
  0.25::double precision,
  'the seed is stored, so a board somebody complains about can be dealt again'
);

select hasnt_column('public', 'sabotage_draft_matches', 'seed',
  'the seed is not on the client-readable match row');

select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'sabotage_draft_private' and tablename = 'boards'
  ),
  'and the table holding it is in no publication'
);

-- ------------------------------------------------------------ table sizes --

insert into tests.fx (k, v) values ('m3', tests.deal_sabotage_draft(3, 0.6));
insert into tests.fx (k, v) values ('m2', tests.deal_sabotage_draft(2, 0.7));
select tests.act_as_admin();

select is(
  (select count(*)::int from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm3')),
  14,
  'a three-player table gets the same fourteen rounds'
);

select is(
  (select count(*)::int from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm2')),
  14,
  'and so does a two-player table'
);

-- --------------------------------------------------------------- the leak --

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm4')
   order by rp.seat limit 1
));

select is(
  (select count(*)::int from public.sabotage_draft_rounds
    where match_id = (select v from tests.fx where k = 'm4')),
  14,
  'a participant can read the whole spin board'
);

select throws_ok(
  'select count(*) from sabotage_draft_private.boards',
  '42501',
  null,
  'the seed is not reachable from an authenticated session at all'
);

select tests.act_as_admin();

select ok(
  not exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'sabotage_draft_private'
       and grantee in ('anon', 'authenticated', 'PUBLIC')
  ),
  'no client role holds any privilege on any table in the engine schema'
);

select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'sabotage_draft_private'
  ),
  'and nothing in it is in a publication'
);

-- Not a closed-set bag_eq: sabotage_draft_picks and sabotage_draft_pick_statuses
-- join the publication in 0052, and this file always runs against the fully
-- migrated database (supabase test db applies every migration first), so a
-- closed list here would start failing the moment 0052 lands. 0052's own test
-- file carries the complete closed-set assertion instead.
select ok(
  (select bool_and(
     exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
     )
   ) from unnest(array[
     'sabotage_draft_matches', 'sabotage_draft_rounds', 'sabotage_draft_players'
   ]) t),
  'the client-readable match, round and player tables this migration adds are all replicated'
);

-- ------------------------------------------------------- the module boundary --

select ok(
  has_schema_privilege('authenticated', 'sabotage_draft', 'usage'),
  'a participant can reach the write-API schema'
);

select ok(
  not has_schema_privilege('authenticated', 'sabotage_draft_private', 'usage'),
  'but not the engine schema — the same shape private has had since 0004'
);

select ok(
  not has_schema_privilege('anon', 'sabotage_draft_private', 'usage'),
  'and anon cannot either'
);

-- --------------------------------------------------------------- refusals --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_thin', tests.mkmatch(2, 'sabotage_draft'));
select tests.act_as_admin();

delete from public.run_participants
 where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm_thin'));

select throws_ok(
  format($$ select sabotage_draft_private.deal_board(%L, 0.1) $$, (select v from tests.fx where k = 'm_thin')),
  'P0001', 'too_few_players',
  'an empty table is refused by the dealer, which is where a game floor belongs'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_start', tests.mkmatch(4, 'sabotage_draft'));

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_start')
   order by rp.seat limit 1
));

select lives_ok(
  format($$ select sabotage_draft.start(%L) $$, (select v from tests.fx where k = 'm_start')),
  'a participant can start the game from a room of four'
);

select tests.act_as_admin();
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'm_start')),
  'playing',
  'starting it moves the match out of setup'
);

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_start')
   order by rp.seat limit 1
));
select throws_ok(
  format($$ select sabotage_draft.start(%L) $$, (select v from tests.fx where k = 'm_start')),
  'P0001', 'match_not_setup',
  'a match that is already playing cannot be dealt again'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('nosy'));
insert into tests.fx (k, v) values ('m_guard', tests.mkmatch(2, 'sabotage_draft'));

select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select sabotage_draft.start(%L) $$, (select v from tests.fx where k = 'm_guard')),
  '42501', 'not_a_participant',
  'someone who is not in the run cannot start its match'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_auction', tests.mkmatch(2));

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_auction')
   order by rp.seat limit 1
));
select throws_ok(
  format($$ select sabotage_draft.start(%L) $$, (select v from tests.fx where k = 'm_auction')),
  'P0001', 'wrong_game',
  'and a match belonging to another game is refused'
);

select * from finish();
rollback;
