-- Season totals are a second private pool derived from the frozen weekly pool.
-- The creation query is deliberately the only derivation: the dealer draws
-- from this private table just as it draws from player_weeks, while clients
-- have neither an endpoint nor a table privilege nor an RLS policy to reach it.
create table private.player_seasons as
select
  player_id,
  season,
  min(display_name) as display_name,
  min(position) as position,
  (array_agg(team order by week desc, team))[1] as team,
  sum(points)::numeric(5,1) as points,
  min(pos_rank) as pos_rank,
  min(tier) as tier
from private.player_weeks
group by player_id, season;

alter table private.player_seasons add primary key (player_id, season);
create index player_seasons_by_position_tier on private.player_seasons (position, tier);
revoke all on table private.player_seasons from public, anon, authenticated;
alter table private.player_seasons enable row level security;

-- A season card has no honest week or opponent. Existing weekly lots retain
-- their values; only newly dealt season lots use the nullable shape.
alter table public.auction_lots
  alter column week drop not null,
  alter column opponent drop not null;

alter table public.auction_matches
  drop constraint auction_matches_scoring_mode_check,
  add constraint auction_matches_scoring_mode_check
    check (scoring_mode in ('weekly', 'season_total'));

drop function private.deal_auction_board(uuid, double precision, text, text);

create function private.deal_auction_board(
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
  v_seed double precision := coalesce(p_seed, random());
  v_n int;
  v_total int;
  v_star int;
  v_solid int;
  v_deep int;
  v_order text[];
  v_slots text[];
  v_tiers text[];
  v_used text[] := '{}';
  v_player_id text;
  v_display_name text;
  v_position text;
  v_season smallint;
  v_week smallint;
  v_team text;
  v_opponent text;
  v_points numeric(5,1);
  v_identity text;
  v_i int;
  v_qb_slots smallint := 1;
  v_rb_slots smallint := 1;
  v_wr_slots smallint := 1;
  v_te_slots smallint := 1;
  v_flex_slots smallint := 1;
  v_purse int := 20;
begin
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  if p_roster_preset is distinct from 'standard' then
    raise exception 'invalid_roster_preset' using errcode = 'P0001';
  end if;

  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  insert into public.auction_players (match_id, user_id, seat, budget)
  select p_match_id, rp.user_id, rp.seat, v_purse
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  select count(*) into v_n from public.auction_players where match_id = p_match_id;
  if v_n < 2 then raise exception 'too_few_players' using errcode = 'P0001'; end if;

  v_total := (v_qb_slots + v_rb_slots + v_wr_slots + v_te_slots + v_flex_slots) * v_n;
  v_star := (7 * v_total) / 20;
  v_solid := (8 * v_total) / 20;
  v_deep := (5 * v_total) / 20;
  select array_agg(t order by rem desc, ord) into v_order
    from (values ('star', (7 * v_total) % 20, 1), ('solid', (8 * v_total) % 20, 2),
                 ('deep', (5 * v_total) % 20, 3)) as remainders(t, rem, ord);
  for v_i in 1 .. (v_total - v_star - v_solid - v_deep) loop
    if v_order[v_i] = 'star' then v_star := v_star + 1;
    elsif v_order[v_i] = 'solid' then v_solid := v_solid + 1;
    else v_deep := v_deep + 1;
    end if;
  end loop;

  select array_agg(position order by random()) into v_slots from (
    select position from unnest(array['QB','RB','WR','TE']) as positions(position),
      generate_series(1, v_n * case position when 'QB' then v_qb_slots when 'RB' then v_rb_slots
                                                when 'WR' then v_wr_slots else v_te_slots end)
  ) base;
  v_slots := v_slots || (select array_agg((array['RB','WR','TE'])[1 + floor(random() * 3)::int])
    from generate_series(1, v_n * v_flex_slots));
  select array_agg(t order by random()) into v_tiers from (
    select 'star' as t from generate_series(1, v_star) union all
    select 'solid' from generate_series(1, v_solid) union all
    select 'deep' from generate_series(1, v_deep)
  ) tokens;

  for v_i in 1 .. v_total loop
    if p_scoring_mode = 'weekly' then
      select player_id, display_name, position, season, week, team, opponent, points
        into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_weeks
       where position = v_slots[v_i] and tier = v_tiers[v_i]
         and not (player_id = any(v_used))
       order by random() limit 1;
      v_identity := v_player_id;
    else
      select player_id, display_name, position, season, null::smallint, team, null::text, points
        into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_seasons
       where position = v_slots[v_i] and tier = v_tiers[v_i]
         and not ((player_id || ':' || season) = any(v_used))
       order by random() limit 1;
      v_identity := v_player_id || ':' || v_season;
    end if;
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_identity;
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, is_flex)
    values (p_match_id, v_i, v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent,
      v_i > v_total - (v_n * v_flex_slots));
    insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_i, v_points);
  end loop;

  insert into public.auction_matches (
    match_id, lot_count, current_lot, opener_seat, scoring_mode, roster_preset,
    qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse
  ) values (
    p_match_id, v_total, 1, 0, p_scoring_mode, p_roster_preset,
    v_qb_slots, v_rb_slots, v_wr_slots, v_te_slots, v_flex_slots, v_purse
  );
  insert into private.auction_boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

create or replace function public.start_auction(
  p_match_id uuid,
  p_scoring_mode text,
  p_roster_preset text
)
returns public.auction_turn
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  if p_roster_preset is distinct from 'standard' then raise exception 'invalid_roster_preset' using errcode = 'P0001'; end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform private.deal_auction_board(p_match_id, null, p_scoring_mode, p_roster_preset);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform private.auction_advance(p_match_id);
  return private.auction_turn_of(p_match_id);
end;
$$;

revoke all on function private.deal_auction_board(uuid, double precision, text, text) from public, anon, authenticated;
revoke all on function public.start_auction(uuid, text, text) from public, anon;
grant execute on function public.start_auction(uuid, text, text) to authenticated;
