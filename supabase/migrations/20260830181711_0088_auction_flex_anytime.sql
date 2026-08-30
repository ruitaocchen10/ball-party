-- FLEX no longer waits for a dedicated round at the end of the board.
--
-- The old rule: base lots (QB/RB/WR/TE) can only fill their natural slot, and
-- FLEX lots -- a fixed N*flex_slots of them, always dealt after every base lot
-- -- are the only lots FLEX can ever come from. That made the schedule
-- trivially safe (the number of RB lots remaining always exactly equalled the
-- number of players still missing one) at the cost of forcing FLEX to sit
-- entirely unused until the very end, even for a player who filled every
-- natural slot early.
--
-- The new rule, validated by simulation before this migration (see the game
-- doc): RB/WR/TE lots are dealt from one shared pool per position, still sized
-- at exactly natural demand plus flex_slots*N total slack (the same total lot
-- count as before — nothing here makes the board longer). A lot may be bid on
-- for FLEX once a player's natural slot for it is full, but only if enough of
-- that exact position remains undealt to cover every OTHER player who still
-- needs it naturally -- counted in remaining slot units, not a headcount of
-- players, which is the bug the prototype caught: a player missing both of
-- their two RB slots needs two units, not one, and undercounting that stranded
-- players in Full and Deep before this rule.
--
-- QB is untouched: never flex-eligible, still dealt at exactly qb_slots*N, so
-- it carries none of this risk either before or after.
--
-- is_flex is dropped rather than repurposed. Under the old rule it was a fact
-- about a lot, fixed at deal time. Under this one, which slot a lot fills
-- depends on the winner's own state at resolution -- any RB/WR/TE lot can end
-- up filling either slot -- so a per-lot flag would no longer describe
-- anything true, and a column that stops meaning what it says is worse than no
-- column.

-- ------------------------------------------------------------------ the dealer --

drop function auction_private.deal_board(uuid, double precision, text, text, smallint, smallint);

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
  -- The flex buffer: N*flex_slots of extra RB/WR/TE supply, split ~evenly
  -- across the three so no one position carries all of it. Total is what the
  -- safety proof needs; the split is cosmetic.
  v_flex_buffer int; v_buf_rb int; v_buf_wr int; v_buf_te int;
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
  -- One shuffle over QB plus RB/WR/TE-with-buffer, rather than shuffling the
  -- base counts and appending flex lots after. Total per position is exactly
  -- what it was before (natural demand for QB; natural demand plus this
  -- position's share of the buffer for RB/WR/TE) -- only the order changes.
  v_flex_buffer := v_n * v_flex_slots;
  v_buf_rb := v_flex_buffer / 3 + (case when v_flex_buffer % 3 > 0 then 1 else 0 end);
  v_buf_wr := v_flex_buffer / 3 + (case when v_flex_buffer % 3 > 1 then 1 else 0 end);
  v_buf_te := v_flex_buffer / 3;
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

revoke all on function auction_private.deal_board(uuid, double precision, text, text, smallint, smallint) from public, anon, authenticated;

-- ---------------------------------------------------------------- eligibility --

CREATE OR REPLACE FUNCTION auction_private.eligible(p_match_id uuid, p_user_id uuid, p_lot_seq smallint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_position text; v_qb smallint; v_rb smallint; v_wr smallint; v_te smallint; v_flex smallint;
  v_limit smallint; v_natural_won int; v_flex_won int; v_remaining int; v_others_need int;
begin
  select l.position, am.qb_slots, am.rb_slots, am.wr_slots, am.te_slots, am.flex_slots
    into v_position, v_qb, v_rb, v_wr, v_te, v_flex
    from public.auction_lots l join public.auction_matches am on am.match_id = l.match_id
   where l.match_id = p_match_id and l.seq = p_lot_seq;

  v_limit := case v_position when 'QB' then v_qb when 'RB' then v_rb when 'WR' then v_wr else v_te end;

  select count(*) into v_natural_won from public.auction_lots
   where match_id = p_match_id and winner_id = p_user_id and slot = v_position;

  -- Natural slot open: always eligible, whatever else is true. This branch
  -- alone is what the old design's whole proof rested on.
  if v_natural_won < v_limit then return true; end if;

  -- Natural full. QB never flexes; nothing left for it to try.
  if v_position = 'QB' then return false; end if;

  select count(*) into v_flex_won from public.auction_lots
   where match_id = p_match_id and winner_id = p_user_id and slot = 'FLEX';
  if v_flex_won >= v_flex then return false; end if;

  -- The guard: how much of this exact position remains genuinely available
  -- (undealt, not just later in seq -- a defensive distinction rather than a
  -- live one, since the game only ever asks this about the current lot, but
  -- "remaining" should mean available regardless), minus this lot itself,
  -- versus how many more units of it every OTHER player still needs
  -- naturally. Units, not a headcount of players who need "any" -- a player
  -- missing both of their two RB slots needs two, not one.
  select count(*) into v_remaining from public.auction_lots
   where match_id = p_match_id and position = v_position and seq >= p_lot_seq and winner_id is null;
  v_remaining := v_remaining - 1;

  select coalesce(sum(greatest(v_limit - w.won, 0)), 0) into v_others_need
    from public.auction_players ap
    left join lateral (
      select count(*) as won from public.auction_lots
       where match_id = p_match_id and winner_id = ap.user_id and slot = v_position
    ) w on true
   where ap.match_id = p_match_id and ap.user_id <> p_user_id;

  return v_remaining >= v_others_need;
end;
$function$
;

-- --------------------------------------------------------------------- resolve --

CREATE OR REPLACE FUNCTION auction_private.resolve(p_match_id uuid, p_seq smallint, p_winner uuid, p_price integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_position text; v_limit smallint; v_natural_won int; v_slot text;
begin
  if p_winner is not null then
    update public.auction_players set budget = budget - p_price where match_id = p_match_id and user_id = p_winner;

    select l.position, case l.position when 'QB' then am.qb_slots when 'RB' then am.rb_slots when 'WR' then am.wr_slots else am.te_slots end
      into v_position, v_limit
      from public.auction_lots l join public.auction_matches am on am.match_id = l.match_id
     where l.match_id = p_match_id and l.seq = p_seq;

    select count(*) into v_natural_won from public.auction_lots
     where match_id = p_match_id and winner_id = p_winner and slot = v_position;

    -- Natural slot first; FLEX only once it's full. eligible() already vetted
    -- that this is safe whenever it isn't the natural fill.
    v_slot := case when v_natural_won < v_limit then v_position else 'FLEX' end;
  end if;

  update public.auction_lots l set winner_id = p_winner, price = p_price,
    slot = case when p_winner is null then null else v_slot end,
    resolved_at = now(), points = (select a.points from private.auction_answers a where a.match_id = l.match_id and a.seq = l.seq)
  where l.match_id = p_match_id and l.seq = p_seq;

  update public.auction_matches set turn_seat = null, turn_deadline = null, free_fallback_seat = null,
    phase = 'sold', phase_deadline = now() + interval '5 seconds' where match_id = p_match_id;
end;
$function$
;

-- --------------------------------------------------------------------- the column --

alter table public.auction_lots drop column is_flex;
