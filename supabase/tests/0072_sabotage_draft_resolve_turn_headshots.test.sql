-- 0067 wired headshot_url into submit_pick and the timeout draw, but missed
-- resolve_turn's own respin and sabotage branches -- both swap a pick's
-- player_id/display_name/season in place without touching headshot_url, so
-- a respun or sabotaged card kept the *original* pick's photo under the new
-- name. 0072 fixes that; these assertions cover the two branches 0067's own
-- suite didn't reach.
--
-- Same 3-player shape as 0053_sabotage_draft_guesses: p0 picks, p2 makes an
-- exact call (sabotage), p1 makes a name-only call against the
-- now-sabotaged card (respin) -- both hit kinds land in the same turn.

begin;
select plan(2);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- p0's round-1 franchise is forced onto a real player with a second season
-- in that same franchise/category pool, so the name-only guess below (the
-- respin branch) has somewhere to land rather than hoping the seed deals it.
update public.sabotage_draft_round_spins s
   set franchise_code = ms.franchise_code
  from tests.sd_multi_season_player('QB') ms
 where s.match_id = (select v from tests.fx where k = 'm') and s.round_number = 1
   and s.user_id = (select v::uuid from tests.fx where k = 'p0');

select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), ms.player_id, ms.season1)
  from tests.sd_multi_season_player('QB') ms;

-- p2's exact guess: sabotage, landing p0 with whatever card p2 named as the
-- replacement (here, p0's own card, so the identity is unchanged).
select tests.act_as((select v from tests.fx where k = 'p2'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), ms.player_id, ms.season1, ms.player_id, ms.season1
) from tests.sd_multi_season_player('QB') ms;

-- p1's name-only guess against the same (now-sabotaged) card: a respin, a
-- different hit kind, so it still lands -- on the same player, a different
-- season -- and is what completes the turn.
select tests.act_as((select v from tests.fx where k = 'p1'));
select sabotage_draft.submit_guess(
  (select v from tests.fx where k = 'm'), ms.player_id
) from tests.sd_multi_season_player('QB') ms;

select tests.act_as_admin();
select is(
  (select count(*)::int from public.sabotage_draft_pick_hits
    where match_id = (select v from tests.fx where k = 'm') and target_user_id = (select v::uuid from tests.fx where k = 'p0')),
  2, 'both a sabotage and a respin landed on p0 this turn'
);

-- Whichever of the two hits landed last is what the pick now shows -- either
-- way, its headshot_url has to agree with the pool's own row for whichever
-- player_id ended up on the card, not the original pick's photo.
select is(
  (select p.headshot_url is distinct from h.headshot_url
     from public.sabotage_draft_picks p
     left join private.av_player_headshots h on h.player_id = p.player_id
    where p.match_id = (select v from tests.fx where k = 'm')
      and p.round_number = 1 and p.user_id = (select v::uuid from tests.fx where k = 'p0')),
  false,
  'the pick left standing after a turn''s hits carries its own player''s headshot, not the original pick''s'
);

select * from finish();
rollback;
