-- Disconnects add presence state, not a second set of game resolutions.
--
-- Since 0063 merged the pick and guess windows into one shared clock, the
-- three disconnect cases the design doc names map onto it like this:
--   - mid-pick timeout: the active seat is absent and never picks -- the
--     ordinary random-respin substitution fires when the shared clock runs
--     out, same as it always has.
--   - already picked, then disconnects: the pick is locked in server-side
--     before the absence happens, so a guess against it -- while the turn
--     is still open -- resolves exactly as if the drafter were present.
--   - mid-turn, no guess or pass submitted: this was already a legal
--     default for a present player, so an absent one just defaults to it
--     too, and the shared clock is what eventually settles the turn anyway.
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

select ok(
  (select bool_and(not absent) from public.sabotage_draft_players
    where match_id = (select v from tests.fx where k = 'm')),
  'every seated player starts present'
);
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'sabotage_draft_players'
      and column_name = 'absent'),
  1,
  'absence is one flag on the existing seated-player state'
);

select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(
  format($$ select sabotage_draft.mark_absent(%L) $$, (select v from tests.fx where k = 'm')),
  'a player can mark only their own live seat absent'
);
select tests.act_as_admin();
select ok((select absent from public.sabotage_draft_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p0')),
  'the disconnected seat is visibly latched absent'
);
select is((select count(*)::int from public.sabotage_draft_players
  where match_id = (select v from tests.fx where k = 'm')),
  3, 'absence does not remove the seat or its eventual roster from the match'
);

-- ------------------------------------------------------ mid-pick timeout --

-- p0 sits at seat 0 and is on the clock from the deal, so their disconnect
-- lands on their own turn. Nobody else has anything pending to resolve, so
-- the shared clock running out both substitutes p0's pick and immediately
-- hands the turn on to p1.
select is(
  (select v::uuid from tests.fx where k = 'p0'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'the absent player happens to be on the clock already'
);
select tests.sd_expire((select v from tests.fx where k = 'm'));
select ok((select by_timeout from public.sabotage_draft_picks
  where match_id = (select v from tests.fx where k = 'm') and round_number = 1
    and user_id = (select v::uuid from tests.fx where k = 'p0')),
  'an absent player follows the existing random-respin timeout path'
);
select is(
  (select v::uuid from tests.fx where k = 'p1'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'and the turn moves straight on -- nothing was pending to resolve against p0''s card'
);

-- ------------------------------------------------ already picked, then gone --

-- p1's round-1 franchise is forced onto a real player with a second season
-- in that same franchise/category pool, so p2's name-only guess below (the
-- respin branch) has somewhere to land rather than hoping the seed deals it.
select tests.act_as_admin();
update public.sabotage_draft_round_spins s
   set franchise_code = ms.franchise_code
  from tests.sd_multi_season_player('QB') ms
 where s.match_id = (select v from tests.fx where k = 'm') and s.round_number = 1
   and s.user_id = (select v::uuid from tests.fx where k = 'p1');

-- p1 picks for real, then disconnects. The pick is already locked in
-- server-side, so a guess against it -- made while the turn is still
-- open -- resolves exactly as if p1 were still present.
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_pick(
  (select v from tests.fx where k = 'm'), ms.player_id, ms.season1
) from tests.sd_multi_season_player('QB') ms;

select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(
  format($$ select sabotage_draft.mark_absent(%L) $$, (select v from tests.fx where k = 'm')),
  'the active drafter can go absent right after locking in their own pick'
);

select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), ms.player_id
) from tests.sd_multi_season_player('QB') ms;

-- p0 never acts against p1's turn -- the third disconnect case, "no guess
-- submitted" is already a legal default, so an absent seat just defaults to
-- it. The turn is still short one action (p0's), so it stays open on its
-- own -- p2's guess alone did not complete it.
select tests.act_as_admin();
select is(
  (select v::uuid from tests.fx where k = 'p1'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'p1''s turn has not advanced yet -- p0''s absence leaves one action unaccounted for'
);
select ok(
  (select turn_deadline > now() from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  'so the shared clock, not early completion, is what will eventually settle it'
);

-- The shared clock is the backstop: it settles the turn regardless of p0's
-- silence, resolving p2's pending guess against p1's absent-but-locked card.
update public.sabotage_draft_matches set turn_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'an expired turn resolves without the absent seat ever acting');
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p1')),
  'respun',
  'a guess against an absent drafter''s already-locked pick resolves normally'
);
select is((select count(*)::int from public.sabotage_draft_guesses
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p0')),
  0, 'no guess row is the same pass an absent player defaults to');
select is((select current_round::int from public.sabotage_draft_matches
  where match_id = (select v from tests.fx where k = 'm')),
  1, 'the shared clock advances the turn, not necessarily the round');
select is(
  (select v::uuid from tests.fx where k = 'p2'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'and the turn has moved on from the absent-but-already-resolved drafter'
);

-- ------------------------------------------------------------- reconnect --

select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(
  format($$ select sabotage_draft.tick(%L) $$, (select v from tests.fx where k = 'm')),
  'the ordinary clock ping works after reconnecting'
);
select tests.act_as_admin();
select ok((select not absent from public.sabotage_draft_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p0')),
  'the first ordinary ping clears absence with no rehydration RPC'
);
select ok((select absent from public.sabotage_draft_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'a different seat''s absence is unaffected by p0''s reconnect'
);
select ok(has_function_privilege('authenticated', 'sabotage_draft.mark_absent(uuid)', 'EXECUTE'),
  'participants can report their own disconnect through the public API');

select * from finish();
rollback;
