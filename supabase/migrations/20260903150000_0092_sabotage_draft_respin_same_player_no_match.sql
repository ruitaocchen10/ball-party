-- 0075's random_pick_same_player has OUT parameters but no `setof`, so it is
-- an ordinary scalar/composite-returning SQL function, not a set-returning
-- one. Postgres's rule for that shape: when the inner query matches zero
-- rows, the function still returns exactly one row -- with every column
-- NULL -- rather than no row at all.
--
-- resolve_turn's `select * into v_drawn from random_pick_same_player(...)`
-- relies on the opposite: 0075's own comment says a player with no other
-- season in the pool should simply miss (`v_exact := found` staying false).
-- Instead FOUND was always true, so a name-only respin guess against a
-- single-season player fell into the "hit" branch and wrote NULL into
-- season/display_name/headshot_url -- the last of which is NOT NULL on
-- sabotage_draft_picks, crashing the turn for real players with only one
-- season in the target franchise/category pool (e.g. Tim Boyle, gnb 2020).
--
-- `returns setof record` makes the zero-match case a genuine zero-row
-- result, so `select ... into ...` correctly sets FOUND := false and the
-- guess takes the miss path resolve_turn already has for it. The query body
-- is unchanged -- its own `limit 1` still caps it at one row when it does
-- find a match.
drop function if exists sabotage_draft_private.random_pick_same_player(text, text[], text, smallint);

create function sabotage_draft_private.random_pick_same_player(
  p_franchise_code text,
  p_categories text[],
  p_player_id text,
  p_exclude_season smallint,
  out player_id text,
  out display_name text,
  out season smallint,
  out headshot_url text
)
returns setof record
language sql
security definer
set search_path = ''
as $$
  select r.player_id, r.display_name, r.season, h.headshot_url
    from private.av_roster_players r
    left join private.av_player_headshots h on h.player_id = r.player_id
   where r.franchise_code = p_franchise_code
     and r.slot_category = any(p_categories)
     and r.player_id = p_player_id
     and r.season <> p_exclude_season
   order by random()
   limit 1;
$$;

-- Dropping and recreating the function resets its grants to the Postgres
-- default (EXECUTE to PUBLIC) -- restate 0075's own revoke for the same
-- reason 0067's comment on random_pick gives.
revoke all on function sabotage_draft_private.random_pick_same_player(text, text[], text, smallint)
  from public, anon, authenticated;
