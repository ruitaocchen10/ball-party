-- A match remembers the format it was dealt with.  These columns deliberately
-- have no defaults: rows from before this migration keep their old shape, while
-- the dealer writes a complete immutable snapshot for every new board.
alter table public.auction_matches
  add column scoring_mode text check (scoring_mode in ('weekly')),
  add column roster_preset text check (roster_preset in ('standard')),
  add column qb_slots smallint check (qb_slots > 0),
  add column rb_slots smallint check (rb_slots > 0),
  add column wr_slots smallint check (wr_slots > 0),
  add column te_slots smallint check (te_slots > 0),
  add column flex_slots smallint check (flex_slots > 0),
  add column purse int check (purse > 0),
  add constraint auction_matches_format_complete check (
    (scoring_mode is null and roster_preset is null and qb_slots is null
      and rb_slots is null and wr_slots is null and te_slots is null
      and flex_slots is null and purse is null)
    or
    (scoring_mode is not null and roster_preset is not null and qb_slots is not null
      and rb_slots is not null and wr_slots is not null and te_slots is not null
      and flex_slots is not null and purse is not null)
  );

-- The dealer owns the resolution rather than relying on table defaults, so a
-- future preset cannot change an old match.  The current standard format is
-- exactly the shipped weekly, five-slot, $20 auction.
drop function private.deal_auction_board(uuid, double precision);

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
  v_seed  double precision := coalesce(p_seed, random());
  v_n     int;
  v_total int;
  v_star  int;
  v_solid int;
  v_deep  int;
  v_order text[];
  v_slots text[];
  v_tiers text[];
  v_used  text[] := '{}';
  v_row   private.player_weeks;
  v_i     int;
  v_qb_slots smallint := 1;
  v_rb_slots smallint := 1;
  v_wr_slots smallint := 1;
  v_te_slots smallint := 1;
  v_flex_slots smallint := 1;
  v_purse int := 20;
begin
  if p_scoring_mode is distinct from 'weekly' then
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
  if v_n < 2 then
    raise exception 'too_few_players' using errcode = 'P0001';
  end if;

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
    select pw.* into v_row from private.player_weeks pw
     where pw.position = v_slots[v_i] and pw.tier = v_tiers[v_i]
       and not (pw.player_id = any (v_used)) order by random() limit 1;
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_row.player_id;
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, is_flex)
    values (p_match_id, v_i, v_row.player_id, v_row.display_name, v_row.position, v_row.season,
      v_row.week, v_row.team, v_row.opponent, v_i > v_total - (v_n * v_flex_slots));
    insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_i, v_row.points);
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

revoke all on function private.deal_auction_board(uuid, double precision, text, text)
  from public, anon, authenticated;

-- Replacing the one-argument entry point rather than overloading it makes the
-- validation unavoidable for direct RPC callers as well as the server action.
drop function public.start_auction(uuid);

create function public.start_auction(
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
  if p_scoring_mode is distinct from 'weekly' then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  if p_roster_preset is distinct from 'standard' then raise exception 'invalid_roster_preset' using errcode = 'P0001'; end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform private.deal_auction_board(p_match_id, null, p_scoring_mode, p_roster_preset);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform private.auction_advance(p_match_id);
  return private.auction_turn_of(p_match_id);
end;
$$;

revoke all on function public.start_auction(uuid, text, text) from public, anon;
grant execute on function public.start_auction(uuid, text, text) to authenticated;
