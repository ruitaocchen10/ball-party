-- A draft ends the moment every seated player's roster (every natural slot
-- plus FLEX) is completely filled -- the same shape a real snake/auction
-- draft has, where nobody keeps picking once every team is done. Today the
-- board only ever checks lot_count: auction_private.advance() finishes the
-- match exactly when current_lot runs past it, so a table always sits
-- through every dealt lot even once nobody at it needs anything more.
--
-- That also removes the cost that kept 0089's flex-buffer floor
-- conservative. A spare lot beyond what a table actually uses either gets
-- dealt with nobody eligible for it (a visible "No sale") or, now, simply
-- never gets reached at all -- the match is already over by the time it
-- would have come up. With that cost gone, the floor moves from one spare
-- per flex-eligible position to two: the same simulation that validated
-- 0089 showed this drives the scarcity guard's block rate on a four-player
-- table from roughly 20% down to roughly 1%, at the cost of reserving a
-- couple more real players per deal who may end up never actually shown.

-- ---------------------------------------------------------- completion --

-- Every natural slot and every FLEX slot, for every seated player, already
-- won. Read live off auction_lots/auction_players/auction_matches rather
-- than tracked separately, the same way eligible() and resolve() already do
-- -- there is no second source of truth to keep in sync.
CREATE FUNCTION auction_private.rosters_complete(p_match_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select not exists (
    select 1
      from public.auction_players ap
      join public.auction_matches am on am.match_id = ap.match_id
     where ap.match_id = p_match_id
       and (
         (select count(*) from public.auction_lots where match_id = p_match_id and winner_id = ap.user_id and slot = 'QB')   < am.qb_slots
         or (select count(*) from public.auction_lots where match_id = p_match_id and winner_id = ap.user_id and slot = 'RB')  < am.rb_slots
         or (select count(*) from public.auction_lots where match_id = p_match_id and winner_id = ap.user_id and slot = 'WR')  < am.wr_slots
         or (select count(*) from public.auction_lots where match_id = p_match_id and winner_id = ap.user_id and slot = 'TE')  < am.te_slots
         or (select count(*) from public.auction_lots where match_id = p_match_id and winner_id = ap.user_id and slot = 'FLEX') < am.flex_slots
       )
  );
$function$
;

revoke all on function auction_private.rosters_complete(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION auction_private.advance(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_board public.auction_matches;
  v_scores jsonb;
begin
  select * into v_board from public.auction_matches where match_id = p_match_id;
  if v_board.current_lot > v_board.lot_count or auction_private.rosters_complete(p_match_id) then
    update public.auction_matches
       set turn_seat = null, turn_deadline = null, phase_deadline = null
     where match_id = p_match_id;
    select jsonb_object_agg(ap.user_id::text, coalesce(w.total, 0)) into v_scores
      from public.auction_players ap left join (
        select winner_id, sum(points) total from public.auction_lots
         where match_id = p_match_id and winner_id is not null group by winner_id
      ) w on w.winner_id = ap.user_id where ap.match_id = p_match_id;
    perform private.finish_match(p_match_id, v_scores);
    return;
  end if;

  update public.auction_matches
     set phase = 'lot_preview', phase_deadline = now() + interval '5 seconds',
         turn_seat = null, turn_deadline = null
   where match_id = p_match_id;
end;
$function$
;

-- ------------------------------------------------------------ the buffer --

CREATE OR REPLACE FUNCTION auction_private.deal_board(
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
  -- The flex buffer: N*flex_slots of extra RB/WR/TE supply, split fairly (a
  -- random subset gets the remainder, not a fixed priority) and floored at
  -- two spares per position (0090 -- was one, see that migration's header
  -- for why a bigger floor is now free of the cost that kept it small).
  v_flex_buffer int; v_buf_rb int; v_buf_wr int; v_buf_te int; v_bump text[];
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

  -- Buffer sizing happens before v_total: v_total has to reflect the actual
  -- buffer, which the floor can grow past flex_slots*N.
  v_flex_buffer := v_n * v_flex_slots;
  v_buf_rb := v_flex_buffer / 3; v_buf_wr := v_flex_buffer / 3; v_buf_te := v_flex_buffer / 3;
  select array_agg(p order by random()) into v_bump from unnest(array['RB', 'WR', 'TE']) p;
  for v_i in 1 .. (v_flex_buffer % 3) loop
    case v_bump[v_i]
      when 'RB' then v_buf_rb := v_buf_rb + 1;
      when 'WR' then v_buf_wr := v_buf_wr + 1;
      else v_buf_te := v_buf_te + 1;
    end case;
  end loop;
  if v_flex_slots > 0 then
    v_buf_rb := greatest(v_buf_rb, 2);
    v_buf_wr := greatest(v_buf_wr, 2);
    v_buf_te := greatest(v_buf_te, 2);
  end if;

  v_total := v_n * v_qb_slots + v_n * v_rb_slots + v_buf_rb + v_n * v_wr_slots + v_buf_wr + v_n * v_te_slots + v_buf_te;
  v_star := (7 * v_total) / 20; v_solid := (8 * v_total) / 20; v_deep := (5 * v_total) / 20;
  select array_agg(t order by rem desc, ord) into v_order from
    (values ('star', (7 * v_total) % 20, 1), ('solid', (8 * v_total) % 20, 2), ('deep', (5 * v_total) % 20, 3)) r(t, rem, ord);
  for v_i in 1 .. (v_total - v_star - v_solid - v_deep) loop
    if v_order[v_i] = 'star' then v_star := v_star + 1; elsif v_order[v_i] = 'solid' then v_solid := v_solid + 1; else v_deep := v_deep + 1; end if;
  end loop;
  -- One shuffle over QB plus RB/WR/TE-with-buffer, rather than shuffling the
  -- base counts and appending flex lots after.
  select array_agg(position order by random()) into v_slots from (
    select position from unnest(array['QB','RB','WR','TE']) positions(position),
      generate_series(1,
        v_n * (case position when 'QB' then v_qb_slots when 'RB' then v_rb_slots when 'WR' then v_wr_slots else v_te_slots end)
        + (case position when 'RB' then v_buf_rb when 'WR' then v_buf_wr when 'TE' then v_buf_te else 0 end))
  ) base;
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
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, headshot_url)
      values (p_match_id, v_i, v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent,
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
