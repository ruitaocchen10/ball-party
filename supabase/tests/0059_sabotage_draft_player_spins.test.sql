-- Every seated player spins their own franchise each round (migration 0059).
-- The composition properties (one spin per player per round, repeats
-- allowed, reproducible from a seed, readable by the whole table) are
-- covered in 0051's own test file, which this migration's schema change
-- touches directly. This file covers what's new to the *resolution* rules:
-- a pick is only ever valid against the picker's own spin, and a guess is
-- only ever valid against the TARGET's spin — never the guesser's.

begin;
select plan(13);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- Force a known mismatch rather than hope the seed deals one: p0 and p1 spin
-- two provably different, real franchises for round one.
update public.sabotage_draft_round_spins s
   set franchise_code = f.f1
  from tests.sd_distinct_franchises('QB') f
 where s.match_id = (select v from tests.fx where k = 'm') and s.round_number = 1
   and s.user_id = (select v::uuid from tests.fx where k = 'p0');
update public.sabotage_draft_round_spins s
   set franchise_code = f.f2
  from tests.sd_distinct_franchises('QB') f
 where s.match_id = (select v from tests.fx where k = 'm') and s.round_number = 1
   and s.user_id = (select v::uuid from tests.fx where k = 'p1');

-- ------------------------------------------------------------- the pick --

select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(
  format(
    $$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'P0001', 'invalid_pick',
  'a card real for someone else''s spin is not valid against your own'
);

select lives_ok(
  format(
    $$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p0')
  ),
  'the same card is valid sourced from the picker''s own spin'
);

-- p0 is the only seat on the clock this turn (see 0062): their pick alone
-- does not close anything -- the shared clock (0063) was already open to
-- both pick and guess from the start of the turn -- and p1, next in turn
-- order but not yet up, cannot pick from even their own, different, spun
-- franchise until it's their turn.
select tests.act_as_admin();
select ok(
  (select turn_deadline > now() from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  'p0''s own pick leaves the shared turn clock open, still aimed at p0'
);
select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(
  format(
    $$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'P0001', 'not_your_turn',
  'p1''s own, different, spun franchise does not matter before it is p1''s turn'
);

-- ------------------------------------------------------------ the guess --

-- p2 tries to sabotage p0 -- the only seat whose turn it is to be guessed at
-- right now -- by naming a card that is real, but only for p1's pool.
-- Resolving the guess against the guesser's own spin (or against the
-- inactive p1's) would be a different, undetected bug from resolving it
-- against nothing at all; resolving it correctly against the active turn's
-- own spin is the only path that raises invalid_guess here, since that card
-- was never p0's to pick.
select tests.act_as((select v from tests.fx where k = 'p2'));
select throws_ok(
  format(
    $$ select sabotage_draft.submit_guess(%L, c.player_id)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'),
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'P0001', 'invalid_guess',
  'a card only valid in a seated non-drafter''s pool is not a legal guess at the active turn'
);

select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), c.player_id
) from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p0'), 'QB') c;

-- The guess is held pending until the turn completes (0063) -- p1 never
-- acts here, so the shared clock is what settles it.
select tests.act_as_admin();
select tests.sd_expire((select v from tests.fx where k = 'm'));
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p2')),
  'respun',
  'the same guess, sourced from the active turn''s own spin, resolves as a genuine hit'
);

-- ----------------------------------------------------------------- options --

select tests.act_as((select v from tests.fx where k = 'p0'));
select is(
  (select array_agg(o::text order by o::text) from sabotage_draft.options((select v from tests.fx where k = 'm')) o),
  (select array_agg(o::text order by o::text) from sabotage_draft.options(
     (select v from tests.fx where k = 'm'), (select v::uuid from tests.fx where k = 'p0')) o),
  'options with no target defaults to the caller''s own spin'
);

select isnt(
  (select array_agg(o::text order by o::text) from sabotage_draft.options((select v from tests.fx where k = 'm')) o),
  (select array_agg(o::text order by o::text) from sabotage_draft.options(
     (select v from tests.fx where k = 'm'), (select v::uuid from tests.fx where k = 'p1')) o),
  'and a different, real target returns a different eligible pool'
);

select throws_ok(
  format($$ select sabotage_draft.options(%L, gen_random_uuid()) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'invalid_target',
  'options refuses a target who is not seated in the match'
);

-- ------------------------------------------------------------ the projection --

select ok(
  not exists (
    select 1 from pg_attribute a
      join pg_type t on t.typrelid = a.attrelid
      join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'sabotage_draft' and t.typname = 'round'
       and a.attname = 'franchise_code' and not a.attisdropped
  ),
  'sabotage_draft.round no longer carries one table-wide franchise_code'
);

select tests.act_as_admin();
select ok(
  exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'sabotage_draft_round_spins'
  ),
  'every player''s spin replicates to the table'
);

select ok(
  has_function_privilege('authenticated', 'sabotage_draft.options(uuid,uuid)', 'EXECUTE'),
  'participants can ask for a specific target''s eligible options'
);
select ok(
  not has_function_privilege('authenticated', 'sabotage_draft_private.spin_franchise(uuid,smallint,uuid)', 'EXECUTE'),
  'but the raw spin lookup itself stays behind the engine schema'
);

select * from finish();
rollback;
