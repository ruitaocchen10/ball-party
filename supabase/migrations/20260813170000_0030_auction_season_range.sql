-- The host picks the era the board is dealt from.
--
-- `docs/games/auction_team_builder.md` fixed the era at 2010-2025 and said to
-- revisit it after playtesting. This makes it a format choice rather than a
-- constant, alongside scoring mode and roster preset: a table that wants only
-- players it watched live deals 2020-2025, and one that wants the whole archive
-- leaves it alone.
--
-- It composes with the tier system for free. `tier` is a *per-season*
-- positional finish (see scripts/player_pool/build_pool.py), so a narrowed
-- window still deals 7:8:5 star/solid/deep — the stars of that window. Nothing
-- in the quota arithmetic has to know the range exists.
--
-- WHY A MINIMUM SPAN: the dealer draws distinct players (`v_used`), and the
-- star band is ranks 1-5 per position per season. A single season therefore
-- offers exactly five star QBs, five star RBs, five star WRs and five star TEs,
-- and a Deep board for four players wants fourteen stars in total. Replaying
-- the dealer's own algorithm against the real pool over every window in the era
-- at two to four players (the lobby capacity, 0009) gives the worst-case rate
-- at which a board cannot be dealt at all:
--
--     span      worst window            pool_exhausted
--     1 year    2013,      deep, 4p     54.6%
--     2 years   2024-2025, deep, 4p      4.9%
--     3 years   2012-2014, deep, 4p      0.2%
--     4 years   -                        0%
--
-- So the floor is four seasons. Three would very nearly do, but four is where
-- every window in the era is clean with room to spare, and the difference is
-- not one a host asking for "recent players" will ever feel. `pool_exhausted`
-- stays as the backstop it already was — this makes it unreachable rather than
-- replacing it, which matters because the tier bands are still being tuned
-- (issue #1) and a retune moves these numbers.

-- ------------------------------------------------------------------- indexes --

-- The dealer's draw becomes `position = ? and tier = ? and season between ? ?`.
-- Season extends the existing index rather than earning a second one: the old
-- two-column index was a prefix of this one, so no existing plan loses ground.
drop index private.player_weeks_by_position_tier;
create index player_weeks_by_position_tier_season
  on private.player_weeks (position, tier, season);

drop index private.player_seasons_by_position_tier;
create index player_seasons_by_position_tier_season
  on private.player_seasons (position, tier, season);

-- --------------------------------------------------------------- the era, once --

-- The selectable bounds are read from the pool, never written down. 0007 gave
-- `player_weeks.season` a lower bound only, on the grounds that a finished
-- season arrives as a new migration and an upper bound would mean altering a
-- constraint every time. A hardcoded 2025 anywhere above the data would break
-- the same way: the 2026 rows would land and nothing would be able to reach
-- them.
create function auction_private.season_bounds(
  out season_min smallint,
  out season_max smallint
)
language sql
stable
security definer
set search_path = ''
as $$ select min(season)::smallint, max(season)::smallint from private.player_weeks $$;

-- The floor from the header, in one place, so the rule the database enforces
-- and the range the host is offered cannot drift apart.
create function auction_private.min_season_span() returns smallint
language sql immutable
as $$ select 4::smallint $$;

-- Resolve-and-refuse, in the shape 0018 established for the rest of the format:
-- the caller's nulls become the full era here rather than in a table default,
-- so a later change to the era cannot reach back and alter an old match, and
-- anything invalid raises instead of being clamped to the nearest legal value.
-- A silently widened range would deal a board the host did not ask for.
create function auction_private.resolve_season_range(
  p_season_from smallint,
  p_season_to smallint,
  out season_from smallint,
  out season_to smallint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_min smallint; v_max smallint;
begin
  select b.season_min, b.season_max into v_min, v_max from auction_private.season_bounds() b;
  season_from := coalesce(p_season_from, v_min);
  season_to   := coalesce(p_season_to, v_max);
  if season_from > season_to then
    raise exception 'invalid_season_range' using errcode = 'P0001';
  end if;
  if season_from < v_min or season_to > v_max then
    raise exception 'season_out_of_range' using errcode = 'P0001';
  end if;
  if season_to - season_from + 1 < auction_private.min_season_span() then
    raise exception 'season_range_too_narrow' using errcode = 'P0001';
  end if;
end;
$$;

-- What the host's picker is built from. The span travels with the bounds for
-- the same reason: the form should be unable to offer a range the dealer will
-- refuse, and it should learn that from the rule rather than restate it.
--
-- A named type rather than bare OUT parameters, so the generated client types
-- name these three fields instead of falling back to an untyped record. Same
-- reason `auction.turn` is a type.
create type auction.era as (
  season_min smallint,
  season_max smallint,
  min_span   smallint
);

create function auction.season_bounds() returns auction.era
language sql
stable
security definer
set search_path = ''
as $$
  select (b.season_min, b.season_max, auction_private.min_season_span())::auction.era
    from auction_private.season_bounds() b
$$;

-- ------------------------------------------------------- the format snapshot --

alter table public.auction_matches
  add column season_from smallint check (season_from >= 2010),
  add column season_to   smallint check (season_to >= 2010),
  add constraint auction_matches_season_ordered check (season_from <= season_to);

-- Boards dealt before this migration were dealt from the whole pool, so the
-- pool's own bounds are not a default standing in for the truth — they are the
-- truth, and recording it is what lets the completeness constraint below cover
-- the new columns. Rows from before 0018 have no format at all and stay empty.
update public.auction_matches m
   set season_from = b.season_min, season_to = b.season_max
  from auction_private.season_bounds() b
 where m.scoring_mode is not null;

alter table public.auction_matches
  drop constraint auction_matches_format_complete,
  add constraint auction_matches_format_complete check (
    (scoring_mode is null and roster_preset is null and qb_slots is null
      and rb_slots is null and wr_slots is null and te_slots is null
      and flex_slots is null and purse is null
      and season_from is null and season_to is null)
    or
    (scoring_mode is not null and roster_preset is not null and qb_slots is not null
      and rb_slots is not null and wr_slots is not null and te_slots is not null
      and flex_slots is not null and purse is not null
      and season_from is not null and season_to is not null)
  );

-- ------------------------------------------------------------------ the dealer --

drop function auction_private.deal_board(uuid, double precision, text, text);

create function auction_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null,
  p_scoring_mode text default 'weekly',
  p_roster_preset text default 'standard',
  p_season_from smallint default null,
  p_season_to smallint default null
)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_seed double precision := coalesce(p_seed, random()); v_n int; v_total int;
  v_star int; v_solid int; v_deep int; v_order text[]; v_slots text[]; v_tiers text[];
  v_used text[] := '{}'; v_player_id text; v_display_name text; v_position text;
  v_season smallint; v_week smallint; v_team text; v_opponent text; v_points numeric(5,1);
  v_i int; v_qb_slots smallint; v_rb_slots smallint; v_wr_slots smallint;
  v_te_slots smallint; v_flex_slots smallint; v_purse int;
  v_from smallint; v_to smallint;
begin
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  case p_roster_preset
    when 'standard' then v_qb_slots := 1; v_rb_slots := 1; v_wr_slots := 1; v_te_slots := 1; v_flex_slots := 1; v_purse := 25;
    when 'full' then v_qb_slots := 1; v_rb_slots := 2; v_wr_slots := 2; v_te_slots := 1; v_flex_slots := 1; v_purse := 35;
    when 'deep' then v_qb_slots := 2; v_rb_slots := 2; v_wr_slots := 3; v_te_slots := 1; v_flex_slots := 2; v_purse := 50;
    else raise exception 'invalid_roster_preset' using errcode = 'P0001';
  end case;
  -- Before the first insert, so a refused range costs nothing and a replayed
  -- format that predates the columns still resolves to the era it was dealt in.
  select r.season_from, r.season_to into v_from, v_to
    from auction_private.resolve_season_range(p_season_from, p_season_to) r;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  insert into public.auction_players (match_id, user_id, seat, budget)
    select p_match_id, rp.user_id, rp.seat, v_purse from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id where m.id = p_match_id;
  select count(*) into v_n from public.auction_players where match_id = p_match_id;
  if v_n < 2 then raise exception 'too_few_players' using errcode = 'P0001'; end if;
  v_total := (v_qb_slots + v_rb_slots + v_wr_slots + v_te_slots + v_flex_slots) * v_n;
  v_star := (7 * v_total) / 20; v_solid := (8 * v_total) / 20; v_deep := (5 * v_total) / 20;
  select array_agg(t order by rem desc, ord) into v_order from
    (values ('star', (7 * v_total) % 20, 1), ('solid', (8 * v_total) % 20, 2), ('deep', (5 * v_total) % 20, 3)) r(t, rem, ord);
  for v_i in 1 .. (v_total - v_star - v_solid - v_deep) loop
    if v_order[v_i] = 'star' then v_star := v_star + 1; elsif v_order[v_i] = 'solid' then v_solid := v_solid + 1; else v_deep := v_deep + 1; end if;
  end loop;
  select array_agg(position order by random()) into v_slots from (
    select position from unnest(array['QB','RB','WR','TE']) positions(position),
      generate_series(1, v_n * case position when 'QB' then v_qb_slots when 'RB' then v_rb_slots when 'WR' then v_wr_slots else v_te_slots end)
  ) base;
  v_slots := v_slots || (select array_agg((array['RB','WR','TE'])[1 + floor(random() * 3)::int]) from generate_series(1, v_n * v_flex_slots));
  select array_agg(t order by random()) into v_tiers from (
    select 'star' t from generate_series(1, v_star) union all select 'solid' from generate_series(1, v_solid) union all select 'deep' from generate_series(1, v_deep)
  ) tokens;
  for v_i in 1 .. v_total loop
    if p_scoring_mode = 'weekly' then
      select player_id, display_name, position, season, week, team, opponent, points into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_weeks where position = v_slots[v_i] and tier = v_tiers[v_i]
          and season between v_from and v_to and not (player_id = any(v_used)) order by random() limit 1;
    else
      select player_id, display_name, position, season, null::smallint, team, null::text, points into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_seasons where position = v_slots[v_i] and tier = v_tiers[v_i]
          and season between v_from and v_to and not (player_id = any(v_used)) order by random() limit 1;
    end if;
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_player_id;
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, is_flex, headshot_url)
      values (p_match_id, v_i, v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_i > v_total - (v_n * v_flex_slots),
        -- Left join in spirit, as in 0013: a player the headshot table has not
        -- caught up with still deals a perfectly good lot, with an empty band.
        (select h.headshot_url from private.player_headshots h where h.player_id = v_player_id));
    insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_i, v_points);
  end loop;
  insert into public.auction_matches (match_id, lot_count, current_lot, opener_seat, scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, season_from, season_to)
    values (p_match_id, v_total, 1, 0, p_scoring_mode, p_roster_preset, v_qb_slots, v_rb_slots, v_wr_slots, v_te_slots, v_flex_slots, v_purse, v_from, v_to);
  insert into private.auction_boards (match_id, seed) values (p_match_id, v_seed);
end;
$function$
;

-- --------------------------------------------------------------- the entry point --

drop function auction.start(uuid, text, text);

-- The era is the one part of the format with an unambiguous meaning when it is
-- absent: no range is the whole pool, which is what every board dealt before
-- this migration was. So unlike scoring mode and roster preset, these two carry
-- defaults — and the default still goes through the same resolver, so "omitted"
-- is a validated choice rather than an unchecked path.
create function auction.start(
  p_match_id uuid,
  p_scoring_mode text,
  p_roster_preset text,
  p_season_from smallint default null,
  p_season_to smallint default null
)
 RETURNS auction.turn
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  if p_roster_preset is distinct from 'standard' and p_roster_preset is distinct from 'full' and p_roster_preset is distinct from 'deep' then raise exception 'invalid_roster_preset' using errcode = 'P0001'; end if;
  -- Refused at the boundary as well as in the dealer, so a direct RPC caller is
  -- turned away before the match row is locked, not after.
  perform auction_private.resolve_season_range(p_season_from, p_season_to);
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform auction_private.deal_board(p_match_id, null, p_scoring_mode, p_roster_preset, p_season_from, p_season_to);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform auction_private.advance(p_match_id); return auction_private.turn_of(p_match_id);
end;
$function$
;

-- ------------------------------------------------------------------- the replay --

-- Replay deals the same format again, and the era is now part of the format.
-- Recreated only to carry the two new columns through; everything else is 0029.
CREATE OR REPLACE FUNCTION public.choose_post_game(p_match_id uuid, p_choice public.post_game_choice)
 RETURNS public.post_game_actions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_match public.matches;
  v_run public.runs;
  v_lobby public.lobbies;
  v_format public.auction_matches;
  v_next_run public.runs;
  v_next_match public.matches;
  v_action public.post_game_actions;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  select * into v_match from public.matches where id = p_match_id;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  select * into v_run from public.runs where id = v_match.run_id;
  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;

  if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if v_match.status <> 'complete'::public.match_status then
    raise exception 'match_not_complete' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.post_game_actions where match_id = p_match_id) then
    raise exception 'post_game_choice_already_made' using errcode = 'P0001';
  end if;

  if p_choice = 'replay'::public.post_game_choice then
    if v_match.game <> 'auction_team_builder' then
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

    select * into v_format from public.auction_matches where match_id = p_match_id;
    if not found or v_format.scoring_mode is null or v_format.roster_preset is null then
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

    insert into public.runs (lobby_id, mode)
    values (v_lobby.id, 'arcade'::public.run_mode)
    returning * into v_next_run;

    insert into public.run_participants (run_id, user_id, seat)
    select v_next_run.id, user_id, seat
      from public.run_participants
     where run_id = v_run.id;

    insert into public.matches (run_id, game, seq, status)
    values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status)
    returning * into v_next_match;

    perform auction_private.deal_board(
      v_next_match.id, null, v_format.scoring_mode, v_format.roster_preset,
      v_format.season_from, v_format.season_to
    );
    update public.matches
       set status = 'playing'::public.match_status, started_at = now()
     where id = v_next_match.id;
    perform auction_private.advance(v_next_match.id);

    insert into public.post_game_actions (match_id, choice, next_match_id)
    values (p_match_id, p_choice, v_next_match.id)
    returning * into v_action;
  else
    insert into public.post_game_actions (match_id, choice)
    values (p_match_id, p_choice)
    returning * into v_action;
  end if;

  return v_action;
end;
$function$
;

-- ------------------------------------------------------------------ privileges --

revoke all on function auction_private.season_bounds()                    from public, anon, authenticated;
revoke all on function auction_private.min_season_span()                  from public, anon, authenticated;
revoke all on function auction_private.resolve_season_range(smallint, smallint) from public, anon, authenticated;
revoke all on function auction_private.deal_board(uuid, double precision, text, text, smallint, smallint) from public, anon, authenticated;

revoke all on function auction.start(uuid, text, text, smallint, smallint) from public, anon;
revoke all on function auction.season_bounds()                            from public, anon;

grant execute on function auction.start(uuid, text, text, smallint, smallint) to authenticated;
grant execute on function auction.season_bounds()                            to authenticated;
