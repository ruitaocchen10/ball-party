-- The guessing window: one wager per player per turn, aimed only at whoever
-- currently holds the turn, and at most one of each hit on a target. The
-- identity remains owner-only even though the outcome is public.
--
-- Since 0063 a guess no longer resolves the instant it's submitted -- it's
-- held pending until the whole turn's action set is complete (the active
-- seat has picked, and every other seat has guessed or passed), so
-- submit_guess's own return value is never the resolved outcome. Every
-- resolved-outcome assertion below re-reads sabotage_draft_guesses instead
-- of trusting what the RPC handed back.

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

-- p0 sits at seat 0 and is on the clock from the deal.
select is(
  (select v::uuid from tests.fx where k = 'p0'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'p0 opens the match on the clock'
);

select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p0'), 'QB') c;

-- p0's own pick does not by itself close anything: p1 and p2 have not yet
-- guessed or passed, so the turn's shared clock stays open and the turn
-- itself has not moved on.
select tests.act_as_admin();
select ok(
  (select turn_deadline > now() from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  'p0''s own pick leaves the shared turn clock open, waiting on p1 and p2'
);
select is(
  (select v::uuid from tests.fx where k = 'p0'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'p0 is still the seat on the clock'
);

-- The seat on the clock has nothing to submit here — a guess is
-- other-directed by construction, so there is no target argument left for
-- p0 to name themselves with.
select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(
  format($$ select sabotage_draft.submit_guess(%L, 'nope') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'not_your_turn', 'the active drafter cannot guess during their own turn'
);

-- p2 knows the fixture's deterministic candidate for p0's own spun franchise
-- and makes an exact call, supplying the same eligible card as the
-- replacement. It is held pending — p1 has not acted yet, so the turn is
-- not complete and nothing has been checked against the actual pick.
select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), c.player_id, c.season, c.player_id, c.season
) from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p0'), 'QB') c;

select tests.act_as_admin();
select ok(
  (select result is null from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p2')),
  'p2''s guess is held pending rather than resolved on the spot'
);
select is(
  (select v::uuid from tests.fx where k = 'p0'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'and the turn has not advanced -- p1 still hasn''t acted'
);

-- The turn is still open, so a second action from the same seat is a
-- duplicate, not a fresh chance.
select tests.act_as((select v from tests.fx where k = 'p2'));
select throws_ok(
  format($$ select sabotage_draft.submit_guess(%L, 'nope') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'already_acted', 'a player spends only one guess-or-pass on this turn'
);

-- p1 calls the same card by name only. This is the last action the turn was
-- waiting on -- p0 has picked, and now both p1 and p2 have acted -- so it
-- resolves both pending guesses, in the order they were made, in the same
-- call: p2's exact guess first (a sabotage hit, since it lands on the real
-- card), then p1's name-only guess against the now-sabotaged card (a
-- respin hit, a different kind, so the per-turn cap does not block it).
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), c.player_id
) from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p0'), 'QB') c;

select tests.act_as_admin();
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p2')),
  'sabotaged', 'the exact guess resolves as a sabotage once the turn completes'
);
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'respun', 'and the name-only guess resolves as a respin — the two hit kinds still both land'
);
select is(
  (select count(*)::int from public.sabotage_draft_pick_hits
    where match_id = (select v from tests.fx where k = 'm') and target_user_id = (select v::uuid from tests.fx where k = 'p0')),
  2, 'a turn can take the design maximum of one respin and one sabotage'
);
select ok(
  (select player_id is not null and season is not null from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1 and user_id = (select v::uuid from tests.fx where k = 'p0')),
  'the respin leaves the target with a complete eligible card'
);
select is(
  (select v::uuid from tests.fx where k = 'p1'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'resolving the last pending guess is itself what completes and advances the turn — no separate clock expiry needed'
);

-- Public guesses give the table an outcome without leaking the target's card.
select tests.act_as((select v from tests.fx where k = 'p2'));
select is((select count(*)::int from public.sabotage_draft_guesses where match_id = (select v from tests.fx where k = 'm')), 2,
  'participants can see the shared guess log');
select is((select count(*)::int from public.sabotage_draft_picks where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p0')), 0,
  'but a target card remains hidden from every other participant');

-- p1 (now active) picks; p2 already spent a guess this round_number —
-- against p0's turn, above — but a guess is scoped to (round, target), not
-- to the round alone, so p2 gets a fresh shot now that p1 holds the turn.
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p1'), 'QB') c;

select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(
  format(
    $$ select sabotage_draft.submit_guess(%L, c.player_id)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'a guesser who already spent a guess this round on a different target gets a fresh one on the new turn'
);

-- p0 never acts against p1's turn; the shared clock is what closes it.
select tests.act_as_admin();
update public.sabotage_draft_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'p1''s turn closes on the clock, with p0 never having acted');
select is(
  (select v::uuid from tests.fx where k = 'p2'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'and the last seat in this match is now on the clock'
);

-- Two structural guarantees: public outcomes replicate, while no browser role
-- can execute the state-transition helpers directly.
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sabotage_draft_guesses'),
  'guesses replicate to the table');
select ok(not has_function_privilege('authenticated', 'sabotage_draft_private.advance_turn(uuid)', 'EXECUTE'),
  'only the engine can advance a turn');
select ok(has_function_privilege('authenticated', 'sabotage_draft.submit_guess(uuid,text,smallint,text,smallint)', 'EXECUTE'),
  'participants can submit guesses through the public API');

select * from finish();
rollback;
