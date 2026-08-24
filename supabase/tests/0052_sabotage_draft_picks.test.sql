-- Tests for the sabotage draft pick, its clock, and the timeout substitution
-- (migration 0052).
--
-- The leak test is the point of this file: a pick's identity and season sit
-- directly on a client-readable, Realtime-published table, protected by RLS
-- rather than by a second physical table (see the header comment on the
-- migration for why). It asserts, from a participant's own session, that
-- nobody but a pick's owner can ever read it back — not through a plain
-- select, and not through anything a Realtime subscription would replicate,
-- since Realtime evaluates the same RLS a select does.
--
-- The timeout test is the other property the design doc names by name: a
-- pick timer that expires with nothing submitted substitutes a random
-- qualifying player and season, not the best available one.

begin;
select plan(26);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p1', user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat limit 1;
insert into tests.fx (k, v)
  select 'p2', user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
  select 'p3', user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat offset 2 limit 1;

-- deal_sabotage_draft goes through the private dealer directly, so the match
-- never left 'setup'. submit_pick requires 'playing', the same as every other
-- game's write path, so bring it into play without going through
-- sabotage_draft.start a second time (which would redeal a different board).
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- ------------------------------------------------------------- the pick --

select tests.act_as((select v from tests.fx where k = 'p1'));

-- Invalid-pick checks come before p1's own real submission below, since
-- afterward p1 has already picked and would hit already_picked first —
-- these are exercised against a player who genuinely has not picked yet.
select throws_ok(
  format($$ select sabotage_draft.submit_pick(%L, 'not-a-real-player-id', 2020::smallint) $$,
    (select v from tests.fx where k = 'm')),
  'P0001', 'invalid_pick',
  'a player who never played this round''s franchise at this round''s slot is refused'
);

select throws_ok(
  format(
    $$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'RB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'P0001', 'invalid_pick',
  'a real player, real season, but the wrong slot category for round one (QB) is refused'
);

select lives_ok(
  format(
    $$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'a participant can submit a pick sourced from their own spun franchise'
);

select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and user_id = (select v from tests.fx where k = 'p1')),
  1,
  'the pick is recorded'
);

select is(
  (select count(*)::int from public.sabotage_draft_pick_statuses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  1,
  'and the presence projection records the lock-in'
);

select throws_ok(
  format(
    $$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
         from tests.sd_pick_candidate(%L, 1::smallint, %L, 'QB') c $$,
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p1')
  ),
  'P0001', 'already_picked',
  'a second pick for the same round is rejected'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));
select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select sabotage_draft.submit_pick(%L, 'whoever', 2020::smallint) $$,
    (select v from tests.fx where k = 'm')),
  '42501', 'not_a_participant',
  'a non-participant cannot submit a pick'
);

-- --------------------------------------------------------------- the leak --

-- p2 has not picked yet. Before p2 picks, RLS still hides p1's identity and
-- season, even though p2 is a full match member who can see the round's
-- public spin freely.
select tests.act_as((select v from tests.fx where k = 'p2'));
select is(
  (select count(*)::int from public.sabotage_draft_pick_statuses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  1,
  'p2 can see that someone has locked in'
);
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1),
  0,
  'but reads back none of that pick''s identity — RLS filters the row, not a column within it'
);

-- p2 picks their own. This is the load-bearing assertion of the whole file:
-- unlike higher_or_lower_calls, having picked does NOT unlock a view of
-- someone else's pick. A sabotage draft pick stays a secret from every other
-- player regardless of what they themselves have done.
select sabotage_draft.submit_pick(
  (select v from tests.fx where k = 'm'), c.player_id, c.season
) from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p2'), 'QB') c;

select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and user_id = (select v from tests.fx where k = 'p2')),
  1,
  'p2 can read their own pick back'
);
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and user_id = (select v from tests.fx where k = 'p1')),
  0,
  'but still cannot read p1''s, even after having picked themselves'
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

select bag_eq(
  $$ select tablename::text from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename like 'sabotage_draft%' $$,
  $$ values ('sabotage_draft_matches'), ('sabotage_draft_rounds'), ('sabotage_draft_players'),
            ('sabotage_draft_round_spins'),
            ('sabotage_draft_picks'), ('sabotage_draft_pick_statuses'),
            ('sabotage_draft_guesses'), ('sabotage_draft_pick_hits'),
            ('sabotage_draft_x_factor_decisions'), ('sabotage_draft_standings'),
            ('sabotage_draft_tiebreak_games') $$,
  'all public sabotage-draft state replicates; picks remain safe on the strength of their RLS policy'
);

select ok(
  has_function_privilege('authenticated', 'sabotage_draft.submit_pick(uuid,text,smallint)', 'EXECUTE'),
  'a participant can reach submit_pick'
);
select ok(
  not has_function_privilege('authenticated', 'sabotage_draft_private.random_pick(text,text[])', 'EXECUTE'),
  'but not the timeout draw it is built from — the engine schema stays private'
);

-- ------------------------------------------------------ simultaneous lock --

-- p3 is the last to pick. The moment their pick lands, the window closes on
-- its own — "picks lock simultaneously" per the design doc — rather than
-- waiting on the clock that is no longer needed.
select ok(
  (select pick_deadline is not null from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  'the pick window is still open with one seat left'
);

select tests.act_as((select v from tests.fx where k = 'p3'));
select sabotage_draft.submit_pick(
  (select v from tests.fx where k = 'm'), c.player_id, c.season
) from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p3'), 'QB') c;

select tests.act_as_admin();
select ok(
  (select pick_deadline is null from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  'and closes the instant the last seat''s pick lands'
);

-- Acting as p1 (who already picked): the deadline check runs before the
-- already-picked check, so this still proves the window itself is shut
-- rather than merely re-proving already_picked.
select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(
  format($$ select sabotage_draft.submit_pick(%L, 'whoever', 2020::smallint) $$,
    (select v from tests.fx where k = 'm')),
  'P0001', 'pick_window_closed',
  'a pick after the window has closed is refused'
);

-- ------------------------------------------------------------- the timeout --

-- A fresh match, this time letting the clock do the work for every seat.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m2', tests.deal_sabotage_draft(3, 0.55));
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm2');

select tests.sd_expire((select v from tests.fx where k = 'm2'));

select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm2') and round_number = 1),
  3,
  'every seat gets a substituted pick once the deadline passes with nothing submitted'
);

select ok(
  (select bool_and(by_timeout) from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm2') and round_number = 1),
  'and every one of them is recorded as timed out rather than chosen'
);

select ok(
  (select pick_deadline is null from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm2')),
  'the window closes once the timeout has filled every seat'
);

-- Not the best available player: the design doc is explicit that this must
-- never be the highest-AV option, on pain of turning a disconnect into a
-- strategy. Asserted directly, across a batch of draws, since a single draw
-- landing on the maximum by chance would not itself disprove the property.
-- Any one player's own round-one spin is enough to exercise the draw — the
-- property under test (variety, not pinned to the max) doesn't depend on
-- whose franchise it is.
select ok(
  (select count(distinct (r).player_id) > 1 from (
     select sabotage_draft_private.random_pick(
       (select franchise_code from public.sabotage_draft_round_spins
         where match_id = (select v from tests.fx where k = 'm2') and round_number = 1
         order by user_id limit 1),
       array['QB']
     ) as r
     from generate_series(1, 20)
   ) draws),
  'the timeout draw is not pinned to one player — repeated draws vary, which the single best option never would'
);

select isnt(
  (select array_agg((r).player_id) from (
     select sabotage_draft_private.random_pick(
       (select franchise_code from public.sabotage_draft_round_spins
         where match_id = (select v from tests.fx where k = 'm2') and round_number = 1
         order by user_id limit 1),
       array['QB']
     ) as r
     from generate_series(1, 20)
   ) draws),
  (select array_agg(top.player_id) from (
     select p.player_id from private.av_roster_players p
      where p.franchise_code = (
            select franchise_code from public.sabotage_draft_round_spins
             where match_id = (select v from tests.fx where k = 'm2') and round_number = 1
             order by user_id limit 1)
        and p.slot_category = 'QB'
      order by p.av desc limit 1
   ) top, generate_series(1, 20)),
  'and is not simply the single highest-AV player repeated twenty times'
);

-- --------------------------------------------------------------- the clock --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m3', tests.deal_sabotage_draft(2, 0.15));
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm3');

select ok(
  (select pick_deadline > now() from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm3')),
  'a dealt match opens with a live pick deadline in the future'
);

select tests.act_as((
  select user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm3') order by seat limit 1
));
select lives_ok(
  format($$ select sabotage_draft.tick(%L) $$, (select v from tests.fx where k = 'm3')),
  'any participant can tick the clock'
);
select is(
  (select count(*)::int from public.sabotage_draft_picks
    where match_id = (select v from tests.fx where k = 'm3')),
  0,
  'and ticking before the deadline does nothing'
);

select * from finish();
rollback;
