-- One shared clock per turn, guesses held pending until the pick lands, and
-- the explicit pass that makes early completion possible.

begin;
select plan(20);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- ------------------------------------------------------- guess before pick --

-- p1 and p2 may guess against p0's turn before p0 has picked at all — the
-- pool (p0's own spun franchise) is public from the moment the turn opens,
-- not from the moment the pick lands.
select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(
  format(
    $$ select sabotage_draft.submit_guess(%L, c.player_id)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p0')
  ),
  'a guess is accepted before the active seat has picked anything'
);
select tests.act_as_admin();
select ok(
  (select result is null from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'and sits pending, since there is nothing yet to check it against'
);
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  0,
  'p0 still has not picked'
);

-- p2 passes rather than guessing — the third possible action, and the one
-- that makes "everyone has acted" knowable at all.
select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(
  format($$ select sabotage_draft.submit_pass(%L) $$, (select v from tests.fx where k = 'm')),
  'a seat may explicitly pass instead of guessing'
);
select is(
  (select count(*)::int from public.sabotage_draft_passes
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')),
  1,
  'the pass is recorded, publicly, the same as a guess would be'
);

-- Now every non-active seat has acted, but p0 has not picked yet — the turn
-- still is not complete, and p0's own pick is what the whole table is
-- waiting on.
select tests.act_as_admin();
select is(
  (select v::uuid from tests.fx where k = 'p0'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'the turn has not advanced -- p0 still has not picked'
);

-- p0's own pick is the last action the turn needed. It resolves p1's
-- pending guess in the same call, then hands the turn on to p1.
select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p0'), 'QB') c;

select tests.act_as_admin();
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'respun',
  'the pending guess resolves the instant the pick it was waiting on lands'
);
select is(
  (select v::uuid from tests.fx where k = 'p1'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'and the active seat''s own pick is what completes and advances the turn -- no clock expiry needed'
);

-- --------------------------------------------------------- already acted --

-- p1 is now active, drafting round 1's QB slot from their own spin.
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p1'), 'QB') c;

-- p2 acts first, leaving p0 as the one action p1's turn is still waiting
-- on -- so p2's own duplicate attempts can be tested against a turn that
-- genuinely has not completed yet.
select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(
  format(
    $$ select sabotage_draft.submit_guess(%L, c.player_id)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'p2 guesses on p1''s turn'
);
select throws_ok(
  format($$ select sabotage_draft.submit_pass(%L) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'already_acted', 'nor pass after already guessing'
);
select throws_ok(
  format($$ select sabotage_draft.submit_guess(%L, 'nope') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'already_acted', 'a seat cannot guess twice on the same turn'
);

-- p0 passes -- the last action p1's turn needed (p2 already guessed): the
-- turn is complete and has already advanced to the last seat.
select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(
  format($$ select sabotage_draft.submit_pass(%L) $$, (select v from tests.fx where k = 'm')),
  'p0 passes on p1''s turn'
);
select tests.act_as_admin();
select is(
  (select v::uuid from tests.fx where k = 'p2'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'a pass counts toward turn completion exactly like a guess does'
);

-- The active seat has no guess or pass to submit either way.
select tests.act_as((select v from tests.fx where k = 'p2'));
select throws_ok(
  format($$ select sabotage_draft.submit_pass(%L) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'not_your_turn', 'the active drafter cannot pass any more than they can guess'
);

-- ------------------------------------------------------------ the timeout --

-- A fresh match: nobody acts at all, so the shared clock alone settles the
-- turn -- the disconnect story's ordinary backstop, unaffected by pass
-- existing as an option nobody here takes.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m2', tests.deal_sabotage_draft(3, 0.55));
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm2');

select tests.sd_expire((select v from tests.fx where k = 'm2'));
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm2') and round_number = 1),
  1,
  'the clock alone substitutes the active seat''s pick with nobody having acted'
);
select is(
  (select count(*)::int from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm2') and round_number = 1),
  0,
  'and settles the turn with no guesses to resolve at all'
);

-- --------------------------------------------------------------- guarding --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));
select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select sabotage_draft.submit_pass(%L) $$, (select v from tests.fx where k = 'm2')),
  '42501', 'not_a_participant', 'a non-participant cannot pass either'
);

select tests.act_as_admin();
select ok(
  not has_function_privilege('authenticated', 'sabotage_draft_private.resolve_turn(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'sabotage_draft_private.turn_complete(uuid,smallint,uuid)', 'EXECUTE'),
  'the batch resolution helpers stay behind the engine schema'
);
select ok(has_function_privilege('authenticated', 'sabotage_draft.submit_pass(uuid)', 'EXECUTE'),
  'participants can reach submit_pass through the public API');
select ok(exists (select 1 from pg_publication_tables
  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sabotage_draft_passes'),
  'passes replicate to the table, the same as a guess''s existence (not its content) already does');

select * from finish();
rollback;
