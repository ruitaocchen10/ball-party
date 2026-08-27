-- The name-only guess's respin (migration 0075): a correct name-only guess
-- no longer voids the whole pick for a brand-new random player -- it keeps
-- the same player and only re-rolls their year, drawn from that player's
-- other seasons in the same franchise/category pool. A player with no other
-- season in that pool has nothing to respin to, so the guess simply misses
-- instead of falling back to a full random draw.
--
-- Both cases play out within round 1, across its first two turns: p0 is
-- seat 0 and active first, then p1 (seat 1) is active next once p0's turn
-- resolves -- there is no need to reach round 2 for either scenario.

begin;
select plan(9);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- ------------------------------------------------------ p0's turn: a hit --

-- p0's round-1 franchise is forced onto a real player with a second season
-- in that same franchise/category pool.
update public.sabotage_draft_round_spins s
   set franchise_code = ms.franchise_code
  from tests.sd_multi_season_player('QB') ms
 where s.match_id = (select v from tests.fx where k = 'm') and s.round_number = 1
   and s.user_id = (select v::uuid from tests.fx where k = 'p0');

select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), ms.player_id, ms.season1)
  from tests.sd_multi_season_player('QB') ms;

-- p1 names the right player but not the year -- a name-only guess. p2
-- passes, so the turn completes the instant p1's guess lands.
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), ms.player_id
) from tests.sd_multi_season_player('QB') ms;

select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_pass((select v from tests.fx where k = 'm'));

select tests.act_as_admin();
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'respun', 'a correct name-only guess still lands as a respin'
);
select ok(
  (select p.player_id = ms.player_id
     from public.sabotage_draft_picks p, tests.sd_multi_season_player('QB') ms
    where p.match_id = (select v from tests.fx where k = 'm') and p.round_number = 1
      and p.user_id = (select v::uuid from tests.fx where k = 'p0')),
  'the respin keeps p0''s pick on the same player p1 named'
);
select ok(
  (select p.season is distinct from ms.season1
     from public.sabotage_draft_picks p, tests.sd_multi_season_player('QB') ms
    where p.match_id = (select v from tests.fx where k = 'm') and p.round_number = 1
      and p.user_id = (select v::uuid from tests.fx where k = 'p0')),
  'and moves the pick to a different year than the one p0 actually had'
);
select ok(
  (select p.season = any(array[ms.season1, ms.season2])
     from public.sabotage_draft_picks p, tests.sd_multi_season_player('QB') ms
    where p.match_id = (select v from tests.fx where k = 'm') and p.round_number = 1
      and p.user_id = (select v::uuid from tests.fx where k = 'p0')),
  'and the year it lands on is a real season this player has in the pool'
);
select is(
  (select v::uuid from tests.fx where k = 'p1'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'a landed respin still completes and advances the turn like any other hit'
);

-- ------------------------------------------------- p1's turn: no-op miss --

-- p1's round-1 franchise is forced onto a real player with exactly one
-- season in that franchise/category pool -- there is no other year to
-- respin to.
update public.sabotage_draft_round_spins s
   set franchise_code = ss.franchise_code
  from tests.sd_single_season_player('QB') ss
 where s.match_id = (select v from tests.fx where k = 'm') and s.round_number = 1
   and s.user_id = (select v::uuid from tests.fx where k = 'p1');

select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), ss.player_id, ss.season)
  from tests.sd_single_season_player('QB') ss;

-- p2 names the right player by name only -- correct, but there is no other
-- year on this card to land on. p0 passes, so the turn still completes.
select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), ss.player_id
) from tests.sd_single_season_player('QB') ss;

select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pass((select v from tests.fx where k = 'm'));

select tests.act_as_admin();
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p1')
      and user_id = (select v::uuid from tests.fx where k = 'p2')),
  'miss', 'a correct name-only guess against a single-season player has nothing to respin to, so it misses'
);
select is(
  (select count(*)::int from public.sabotage_draft_pick_hits
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p1')),
  0, 'no hit is recorded for a guess that could not have changed anything'
);
select ok(
  (select p.player_id = ss.player_id and p.season = ss.season
     from public.sabotage_draft_picks p, tests.sd_single_season_player('QB') ss
    where p.match_id = (select v from tests.fx where k = 'm') and p.round_number = 1
      and p.user_id = (select v::uuid from tests.fx where k = 'p1')),
  'and the pick stands exactly as p1 left it'
);
select is(
  (select v::uuid from tests.fx where k = 'p2'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'the turn still completes and advances even though the guess whiffed'
);

select * from finish();
rollback;
