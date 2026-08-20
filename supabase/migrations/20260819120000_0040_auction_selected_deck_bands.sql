-- A format chooses its deck before it chooses difficulty.  The old dealer
-- filtered rows by the tier each player finished in *within a season*, which
-- meant the same "star" token described a different fraction of a weekly
-- window, a season-total window, and the full pool.  Rank the selected deck
-- instead: the 7:8:5 mix remains the board's shape, while each band now means
-- the same percentile of the cards actually in play.
--
-- There is intentionally no minimum era span.  The deck rank normalises to
-- the chosen rows, and player distinctness is enforced by the draw itself, so
-- a single season is a real format choice rather than an invalid approximation
-- of a larger one.

create or replace function auction_private.min_season_span() returns smallint
language sql immutable
as $$ select 1::smallint $$;

create or replace function auction_private.resolve_season_range(
  p_season_from smallint,
  p_season_to smallint,
  out season_from smallint,
  out season_to smallint
)
returns record
language plpgsql
security definer
set search_path = ''
as $$
declare v_min smallint; v_max smallint;
begin
  select b.season_min, b.season_max into v_min, v_max from auction_private.season_bounds() b;
  season_from := coalesce(p_season_from, v_min);
  season_to := coalesce(p_season_to, v_max);
  if season_from > season_to then
    raise exception 'invalid_season_range' using errcode = 'P0001';
  end if;
  if season_from < v_min or season_to > v_max then
    raise exception 'season_out_of_range' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function auction_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null,
  p_scoring_mode text default 'season_total',
  p_roster_preset text default 'standard',
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
      with ranked_deck as (
        select pw.*, ntile(20) over (partition by pw.position order by pw.points desc, pw.player_id, pw.season, pw.week) as quantile
          from private.player_weeks pw
         where pw.season between v_from and v_to
      )
      select player_id, display_name, position, season, week, team, opponent, points
        into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from ranked_deck
       where position = v_slots[v_i]
         and case when quantile <= 7 then 'star' when quantile <= 15 then 'solid' else 'deep' end = v_tiers[v_i]
         and not (player_id = any(v_used))
       order by random() limit 1;
    else
      with ranked_deck as (
        select ps.*, ntile(20) over (partition by ps.position order by ps.points desc, ps.player_id, ps.season) as quantile
          from private.player_seasons ps
         where ps.season between v_from and v_to
      )
      select player_id, display_name, position, season, null::smallint, team, null::text, points
        into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from ranked_deck
       where position = v_slots[v_i]
         and case when quantile <= 7 then 'star' when quantile <= 15 then 'solid' else 'deep' end = v_tiers[v_i]
         and not (player_id = any(v_used))
       order by random() limit 1;
    end if;
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_player_id;
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, is_flex, headshot_url)
      values (p_match_id, v_i, v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_i > v_total - (v_n * v_flex_slots),
        (select h.headshot_url from private.player_headshots h where h.player_id = v_player_id));
    insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_i, v_points);
  end loop;
  insert into public.auction_matches (match_id, lot_count, current_lot, opener_seat, scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, season_from, season_to)
    values (p_match_id, v_total, 1, 0, p_scoring_mode, p_roster_preset, v_qb_slots, v_rb_slots, v_wr_slots, v_te_slots, v_flex_slots, v_purse, v_from, v_to);
  insert into private.auction_boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;
