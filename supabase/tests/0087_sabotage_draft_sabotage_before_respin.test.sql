-- Sabotage-before-respin ordering (migration 0087): when a turn's last
-- action resolves two pending guesses of different kinds against the same
-- pick, the exact guess (player + season) now always resolves first,
-- regardless of which guess was actually submitted to the database first.
--
-- p1 guesses name-only (submits first); p2 guesses exact, naming a genuinely
-- different replacement card (submits second, and completes the turn). Pre-
-- 0087, submission order alone decided this: p1's respin would land first
-- and redraw the season, leaving p2's exact guess checked against a pick
-- that no longer matched -- a miss, despite p2 having done the harder thing.
-- 0087 makes the exact guess win regardless of who acted first.

begin;
select plan(5);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- p0's round-1 franchise is forced onto a real multi-season player, same as
-- 0075/0053, so there's a known card for p1 and p2 to both guess at.
update public.sabotage_draft_round_spins s
   set franchise_code = ms.franchise_code
  from tests.sd_multi_season_player('QB') ms
 where s.match_id = (select v from tests.fx where k = 'm') and s.round_number = 1
   and s.user_id = (select v::uuid from tests.fx where k = 'p0');

select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), ms.player_id, ms.season1)
  from tests.sd_multi_season_player('QB') ms;

-- p1 names the card by player only -- submitted first, so it holds the
-- lower id -- and is held pending; p2 hasn't acted yet.
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), ms.player_id
) from tests.sd_multi_season_player('QB') ms;

-- p2 names the same card exactly, with a genuinely different player as the
-- replacement -- so if this lands, the pick changes to someone else
-- entirely, not back to itself. This is the turn's last pending action, so
-- it's what triggers resolve_turn.
select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), ms.player_id, ms.season1, other.player_id, other.season
) from tests.sd_multi_season_player('QB') ms,
       tests.sd_other_player(ms.franchise_code, 'QB', ms.player_id) other;

select tests.act_as_admin();
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p2')),
  'sabotaged',
  'p2''s exact guess lands as a sabotage even though it was submitted second'
);
select is(
  (select result::text from public.sabotage_draft_guesses
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1
      and target_user_id = (select v::uuid from tests.fx where k = 'p0')
      and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'miss',
  'p1''s earlier name-only guess now misses -- the sabotage already swapped the pick to someone else by the time it''s checked'
);
select is(
  (select count(*)::int from public.sabotage_draft_pick_hits
    where match_id = (select v from tests.fx where k = 'm') and target_user_id = (select v::uuid from tests.fx where k = 'p0')),
  1,
  'only the sabotage hit lands this turn -- the respin never gets a real chance to'
);
select ok(
  (select p.player_id = other.player_id and p.season = other.season
     from public.sabotage_draft_picks p,
          tests.sd_multi_season_player('QB') ms,
          tests.sd_other_player(ms.franchise_code, 'QB', ms.player_id) other
    where p.match_id = (select v from tests.fx where k = 'm') and p.round_number = 1
      and p.user_id = (select v::uuid from tests.fx where k = 'p0')),
  'the pick ends up as p2''s chosen replacement, not respun'
);
select is(
  (select v::uuid from tests.fx where k = 'p1'),
  tests.sd_active_user((select v from tests.fx where k = 'm')),
  'the turn still advances once both guesses are resolved'
);

select * from finish();
rollback;
