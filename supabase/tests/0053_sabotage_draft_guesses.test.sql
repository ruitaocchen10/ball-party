-- The guessing window: one wager per player, and at most one of each hit on
-- a target.  The identity remains owner-only even though the outcome is public.

begin;
select plan(16);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- Lock all three picks, which opens the public guessing phase.
select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p0'), 'QB') c;
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p1'), 'QB') c;
select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), c.player_id, c.season)
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p2'), 'QB') c;

select tests.act_as_admin();
select ok((select pick_deadline is null and guess_deadline > now() from public.sabotage_draft_matches
  where match_id = (select v from tests.fx where k = 'm')),
  'the last pick opens a guess window instead of ending the round');

-- p2 knows the fixture's deterministic candidate for p1's own spun franchise
-- and makes an exact call, supplying the same eligible card as the
-- replacement.  p0 then calls that card by name only, proving the two hit
-- kinds work in either order.
select tests.act_as((select v from tests.fx where k = 'p2'));
select is(
  (select g.result::text
     from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p1'), 'QB') c
     cross join lateral sabotage_draft.submit_guess(
       (select v from tests.fx where k = 'm'), (select v::uuid from tests.fx where k = 'p1'), c.player_id, c.season, c.player_id, c.season
     ) g),
  'sabotaged', 'a correct name-and-year guess installs the supplied eligible replacement'
);

select tests.act_as_admin();
select is((select count(*)::int from public.sabotage_draft_pick_hits where match_id = (select v from tests.fx where k = 'm') and target_user_id = (select v::uuid from tests.fx where k = 'p1') and kind = 'sabotage'), 1,
  'the target has exactly one exact-sabotage hit');

select tests.act_as((select v from tests.fx where k = 'p0'));
select is(
  (select g.result::text
     from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p1'), 'QB') c
     cross join lateral sabotage_draft.submit_guess(
       (select v from tests.fx where k = 'm'), (select v::uuid from tests.fx where k = 'p1'),
       c.player_id
     ) g),
  'respun', 'a correct player-only guess re-spins the target card'
);

select tests.act_as_admin();
select is((select count(*)::int from public.sabotage_draft_pick_hits where match_id = (select v from tests.fx where k = 'm') and target_user_id = (select v::uuid from tests.fx where k = 'p1')), 2,
  'a slot can take the design maximum of one respin and one sabotage');
select ok((select player_id is not null and season is not null from public.sabotage_draft_picks where match_id = (select v from tests.fx where k = 'm') and round_number = 1 and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'the respin leaves the target with a complete eligible card');

select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(
  format($$ select sabotage_draft.submit_guess(%L, %L, 'nope') $$, (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p2')),
  'P0001', 'already_guessed', 'a player spends only one guess per round'
);
select throws_ok(
  format($$ select sabotage_draft.submit_guess(%L, %L, 'nope') $$, (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p0')),
  'P0001', 'invalid_target', 'a player cannot aim a guess at their own hidden pick'
);

-- Public guesses give the table an outcome without leaking the target's card.
select tests.act_as((select v from tests.fx where k = 'p2'));
select is((select count(*)::int from public.sabotage_draft_guesses where match_id = (select v from tests.fx where k = 'm')), 2,
  'participants can see the shared guess log');
select is((select count(*)::int from public.sabotage_draft_picks where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p1')), 0,
  'but a target card remains hidden from every other participant');

select tests.act_as_admin();
update public.sabotage_draft_matches set guess_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'the server closes an expired guess window');
select is((select current_round::int from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'm')), 2,
  'and advances the match to the next pick round');
select ok((select pick_deadline > now() and guess_deadline is null from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'm')),
  'the next round opens its own simultaneous pick clock');

-- Two structural guarantees: public outcomes replicate, while no browser role
-- can execute the state-transition helpers directly.
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sabotage_draft_guesses'),
  'guesses replicate to the table');
select ok(not has_function_privilege('authenticated', 'sabotage_draft_private.advance_round(uuid)', 'EXECUTE'),
  'only the engine can advance a round');
select ok(has_function_privilege('authenticated', 'sabotage_draft.submit_guess(uuid,uuid,text,smallint,text,smallint)', 'EXECUTE'),
  'participants can submit guesses through the public API');

select * from finish();
rollback;
