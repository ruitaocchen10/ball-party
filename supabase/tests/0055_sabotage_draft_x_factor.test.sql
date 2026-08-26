-- Round fourteen reuses the ordinary pick/guess machinery, one seat's turn
-- at a time, then opens that seat's own self-only replacement-or-discard
-- decision once their guess window has settled — before the turn moves on.
begin;
select plan(24);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- The first thirteen rounds are immaterial to the X-Factor's own path;
-- settle every seat's turn in every one of them through the ordinary
-- timeout and guess-expiry transitions — three seats per round, thirteen
-- rounds, one full turn (pick timeout, then an unused guess window) each.
do $$
declare i int; v_match uuid := (select v::uuid from tests.fx where k = 'm');
begin
  for i in 1 .. 39 loop
    perform tests.sd_expire_turn(v_match);
  end loop;
end $$;

select is((select slot from public.sabotage_draft_rounds
  where match_id = (select v from tests.fx where k = 'm') and round_number = 14),
  'X_FACTOR', 'round 14 remains the ordinary X_FACTOR round');
select is((select current_round::int from public.sabotage_draft_matches
  where match_id = (select v from tests.fx where k = 'm')), 14,
  'the ordinary round transition arrives at round 14');
select is(
  (select v::uuid from tests.fx where k = 'p0'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'and turn order opens round 14 the same way it opens any other'
);

-- ---------------------------------------------------------------- p0's turn --

select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(format($$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
  from tests.sd_pick_candidate(%L, 14::smallint, %L, 'QB') c $$,
  (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p0')),
  'the X-Factor accepts a QB from its spun franchise, through the unchanged pick API');

select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'QB') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'x_factor_not_ready',
  'the drafter cannot decide while their own guess window is still open');

-- No special resolution: the ordinary shared-clock expiry is the sole
-- transition into the decision phase.
select tests.act_as_admin();
update public.sabotage_draft_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'p0''s ordinary turn expiry settles their round-14 turn');
select ok((select x_factor_open and turn_deadline is null
  from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'm')),
  'settlement opens only p0''s own post-guess X-Factor decision');

select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'OL') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'invalid_x_factor_slot',
  'only the seven named offensive skill slots are valid replacement targets');
select is((select replace_slot from sabotage_draft.submit_x_factor_decision(
  (select v from tests.fx where k = 'm'), 'QB')),
  'QB', 'the drafter can replace exactly one named existing skill slot');
select is(
  (select v::uuid from tests.fx where k = 'p1'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'p0''s own decision -- not a shared phase -- is what hands the turn to the next seat'
);

-- x_factor_already_decided still guards the seat directly, defense-in-depth
-- against a repeat decision landing after the phase somehow reopened (a
-- race, a bug elsewhere) — exercised here by reopening p0's turn
-- artificially, since the ordinary turn sequence has already moved on to p1
-- and never comes back to p0 this match.
select tests.act_as_admin();
update public.sabotage_draft_matches set active_seat = 0, x_factor_open = true, turn_deadline = null
 where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'RB1') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'x_factor_already_decided',
  'a final decision cannot be repurposed into another replacement, even with the phase artificially reopened'
);
select tests.act_as_admin();
update public.sabotage_draft_matches set active_seat = 1, x_factor_open = false, turn_deadline = now() + interval '45 seconds'
 where match_id = (select v from tests.fx where k = 'm');

-- ---------------------------------------------------------------- p1's turn --

select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(format($$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
  from tests.sd_pick_candidate(%L, 14::smallint, %L, 'RB') c $$,
  (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')),
  'the same pick API accepts an RB from the next seat''s own turn');
select tests.act_as_admin();
update public.sabotage_draft_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'p1''s own turn expiry settles their turn too');
select tests.act_as((select v from tests.fx where k = 'p1'));
select is((select replace_slot is null from sabotage_draft.submit_x_factor_decision(
  (select v from tests.fx where k = 'm'), null)), true,
  'NULL is the explicit discard choice');
select is(
  (select v::uuid from tests.fx where k = 'p2'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'and the last seat in this match is now on the clock'
);

-- ---------------------------------------------------------------- p2's turn --

select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(format($$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
  from tests.sd_pick_candidate(%L, 14::smallint, %L, 'WR') c $$,
  (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p2')),
  'the same pick API accepts a WR from the last seat''s own turn');
select tests.act_as_admin();
update public.sabotage_draft_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'p2''s turn expiry settles the last turn of the match');
select tests.act_as((select v from tests.fx where k = 'p2'));
select is((select replace_slot from sabotage_draft.submit_x_factor_decision(
  (select v from tests.fx where k = 'm'), 'WR3')),
  'WR3', 'each drafter independently chooses one of their own skill slots — the last decision triggers the season');

-- There is no fifteenth pick/guess path: the decision overlays the existing
-- round-14 card and is unavailable to submit_guess after its window closed.
select tests.act_as_admin();
select is((select count(*)::int from public.sabotage_draft_picks
  where match_id = (select v from tests.fx where k = 'm')), 42,
  'three players finish with the original fourteen picks each, never a fifteenth');
select is((select count(*)::int from public.sabotage_draft_x_factor_decisions
  where match_id = (select v from tests.fx where k = 'm')), 3,
  'every player has one final replacement-or-discard decision');
select is((select count(*)::int from public.sabotage_draft_guesses
  where match_id = (select v from tests.fx where k = 'm') and round_number = 14), 0,
  'the post-guess decision creates no guess records');
select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(format($$ select sabotage_draft.submit_guess(%L, 'nope') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'match_not_playing',
  'no player can target the decision once the resulting season has completed');

select tests.act_as_admin();
select ok(has_function_privilege('authenticated', 'sabotage_draft.submit_x_factor_decision(uuid,text)', 'EXECUTE'),
  'the self-only X-Factor decision API is available to participants');
select ok(exists (select 1 from pg_publication_tables
  where pubname = 'supabase_realtime' and schemaname = 'public'
    and tablename = 'sabotage_draft_x_factor_decisions'),
  'final decisions replicate to the match table');

select * from finish();
rollback;
