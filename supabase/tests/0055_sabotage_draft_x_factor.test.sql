-- Round fourteen reuses the ordinary pick/guess machinery, then opens a
-- self-only replacement-or-discard decision once that window has settled.
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

-- The first thirteen rounds are immaterial to the X-Factor's shared path;
-- settle each through the ordinary timeout and guess-expiry transitions.
do $$
declare i int;
begin
  for i in 1 .. 13 loop
    update public.sabotage_draft_matches set pick_deadline = now() - interval '1 second'
     where match_id = (select v::uuid from tests.fx where k = 'm');
    perform sabotage_draft_private.expire((select v::uuid from tests.fx where k = 'm'));
    update public.sabotage_draft_matches set guess_deadline = now() - interval '1 second'
     where match_id = (select v::uuid from tests.fx where k = 'm');
    perform sabotage_draft_private.expire((select v::uuid from tests.fx where k = 'm'));
  end loop;
end $$;

select is((select slot from public.sabotage_draft_rounds
  where match_id = (select v from tests.fx where k = 'm') and round_number = 14),
  'X_FACTOR', 'round 14 remains the ordinary X_FACTOR round');
select is((select current_round::int from public.sabotage_draft_matches
  where match_id = (select v from tests.fx where k = 'm')), 14,
  'the ordinary round transition arrives at round 14');

-- Different skill categories all pass through the unchanged submit_pick API.
select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(format($$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
  from tests.sd_pick_candidate(%L, 14::smallint, 'QB') c $$,
  (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm')),
  'the X-Factor accepts a QB from its spun franchise');
select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(format($$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
  from tests.sd_pick_candidate(%L, 14::smallint, 'RB') c $$,
  (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm')),
  'the same pick API accepts an RB');
select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(format($$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
  from tests.sd_pick_candidate(%L, 14::smallint, 'WR') c $$,
  (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm')),
  'the same pick API accepts a WR');

select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'QB') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'x_factor_not_ready',
  'the drafter cannot decide while the normal shared guess window is still open');

-- No special resolution: ordinary guess expiry is the sole transition into
-- the decision phase.
select tests.act_as_admin();
update public.sabotage_draft_matches set guess_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'the ordinary guess expiry settles round 14');
select ok((select x_factor_open and pick_deadline is null and guess_deadline is null
  from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'm')),
  'settlement opens only the post-guess X-Factor decision phase');

select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'OL') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'invalid_x_factor_slot',
  'only the seven named offensive skill slots are valid replacement targets');
select is((select replace_slot from sabotage_draft.submit_x_factor_decision(
  (select v from tests.fx where k = 'm'), 'QB')),
  'QB', 'the drafter can replace exactly one named existing skill slot');
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'RB1') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'x_factor_already_decided',
  'the replacement is a final call, not a source of extra roster slots');
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'OL') $$,
  (select v from tests.fx where k = 'm')),
  'P0001', 'x_factor_already_decided',
  'a final decision cannot be repurposed into another replacement');

select tests.act_as((select v from tests.fx where k = 'p1'));
select is((select replace_slot is null from sabotage_draft.submit_x_factor_decision(
  (select v from tests.fx where k = 'm'), null)), true,
  'NULL is the explicit discard choice');
select tests.act_as((select v from tests.fx where k = 'p2'));
select is((select replace_slot from sabotage_draft.submit_x_factor_decision(
  (select v from tests.fx where k = 'm'), 'WR3')),
  'WR3', 'each drafter independently chooses one of their own skill slots');

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
select throws_ok(format($$ select sabotage_draft.submit_guess(%L, %L, 'nope') $$,
  (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p0')),
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
