-- Roster presets are labels for a resolved shape, never a live lookup. A match
-- keeps the counts and purse it was dealt with even if this mapping is retuned.
alter table public.auction_matches
  drop constraint auction_matches_roster_preset_check,
  add constraint auction_matches_roster_preset_check
    check (roster_preset in ('standard', 'full', 'deep'));

-- A slot may be won up to its frozen capacity. The lot schedule continues to
-- assign base lots to their natural slot and flex lots to FLEX, so no choice is
-- introduced here and the one-for-one no-stranding proof still applies.
create or replace function private.auction_eligible(p_match_id uuid, p_user_id uuid, p_lot_seq smallint)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select count(w.*) < case when l.is_flex then am.flex_slots else
    case l.position when 'QB' then am.qb_slots when 'RB' then am.rb_slots
                    when 'WR' then am.wr_slots else am.te_slots end end
    from public.auction_lots l
    join public.auction_matches am on am.match_id = l.match_id
    left join public.auction_lots w
      on w.match_id = p_match_id and w.winner_id = p_user_id
     and w.slot = case when l.is_flex then 'FLEX' else l.position end
   where l.match_id = p_match_id and l.seq = p_lot_seq
   group by l.is_flex, l.position, am.qb_slots, am.rb_slots, am.wr_slots, am.te_slots, am.flex_slots;
$$;

create or replace function private.deal_auction_board(
  p_match_id uuid,
  p_seed double precision default null,
  p_scoring_mode text default 'weekly',
  p_roster_preset text default 'standard'
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
  v_identity text; v_i int; v_qb_slots smallint; v_rb_slots smallint; v_wr_slots smallint;
  v_te_slots smallint; v_flex_slots smallint; v_purse int;
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
        from private.player_weeks where position = v_slots[v_i] and tier = v_tiers[v_i] and not (player_id = any(v_used)) order by random() limit 1;
      v_identity := v_player_id;
    else
      select player_id, display_name, position, season, null::smallint, team, null::text, points into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_seasons where position = v_slots[v_i] and tier = v_tiers[v_i] and not ((player_id || ':' || season) = any(v_used)) order by random() limit 1;
      v_identity := v_player_id || ':' || v_season;
    end if;
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_identity;
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, is_flex)
      values (p_match_id, v_i, v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_i > v_total - (v_n * v_flex_slots));
    insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_i, v_points);
  end loop;
  insert into public.auction_matches (match_id, lot_count, current_lot, opener_seat, scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse)
    values (p_match_id, v_total, 1, 0, p_scoring_mode, p_roster_preset, v_qb_slots, v_rb_slots, v_wr_slots, v_te_slots, v_flex_slots, v_purse);
  insert into private.auction_boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

create or replace function public.start_auction(p_match_id uuid, p_scoring_mode text, p_roster_preset text)
returns public.auction_turn
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  if p_roster_preset is distinct from 'standard' and p_roster_preset is distinct from 'full' and p_roster_preset is distinct from 'deep' then raise exception 'invalid_roster_preset' using errcode = 'P0001'; end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform private.deal_auction_board(p_match_id, null, p_scoring_mode, p_roster_preset);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform private.auction_advance(p_match_id); return private.auction_turn_of(p_match_id);
end;
$$;
