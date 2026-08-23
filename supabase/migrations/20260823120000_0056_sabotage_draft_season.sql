-- Sabotage draft: turn each final roster into a reproducible 17-game season.
--
-- A game between rosters with strengths A and B gives A this probability:
--
--   1 / (1 + exp(-((A - B) / 25)))
--
-- 25 AV is deliberately a noticeable, rather than overwhelming, edge: it
-- makes a better draft the favourite while leaving enough room for a season
-- (and a one-game tiebreak) to be surprising.  Season games are independent
-- games against the table's mean roster strength.  A tiebreak game substitutes
-- the paired opponent's actual strength into the exact same formula.

create table public.sabotage_draft_standings (
  match_id        uuid not null references public.matches (id) on delete cascade,
  user_id         uuid not null,
  roster_strength integer not null,
  wins            smallint not null check (wins between 0 and 17),
  losses          smallint not null check (losses between 0 and 17),
  tiebreak_rank   smallint not null check (tiebreak_rank >= 1),
  primary key (match_id, user_id),
  foreign key (match_id, user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  check (wins + losses = 17)
);

-- The bracket is persisted rather than inferred from a final ordering.  It
-- makes a bye and every decisive one-off game inspectable after the match.
create table public.sabotage_draft_tiebreak_games (
  match_id      uuid not null references public.matches (id) on delete cascade,
  record_wins   smallint not null,
  bracket_round smallint not null check (bracket_round >= 1),
  game_number   smallint not null check (game_number >= 1),
  player_a      uuid not null,
  player_b      uuid,
  winner_user_id uuid not null,
  primary key (match_id, record_wins, bracket_round, game_number),
  foreign key (match_id, player_a) references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  foreign key (match_id, player_b) references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  foreign key (match_id, winner_user_id) references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  check (player_b is null or player_b <> player_a),
  check (winner_user_id = player_a or winner_user_id = player_b)
);

create table sabotage_draft_private.seasons (
  match_id uuid primary key references public.matches (id) on delete cascade,
  seed     double precision not null,
  simulated_at timestamptz not null default now()
);

revoke all on table sabotage_draft_private.seasons from public, anon, authenticated;
alter table sabotage_draft_private.seasons enable row level security;

create function sabotage_draft_private.win_probability(p_strength_a integer, p_strength_b integer)
returns double precision
language sql immutable set search_path = '' as $$
  select 1.0 / (1.0 + exp(-((p_strength_a - p_strength_b)::double precision / 25.0)));
$$;

-- Assemble exactly the final roster, not the draft history: rounds 1-13
-- supply the fixed slots and an accepted X-Factor replaces its chosen slot.
-- A discarded X-Factor therefore contributes no extra (fifteenth) player.
create function sabotage_draft_private.roster_strengths(p_match_id uuid)
returns table (user_id uuid, roster_strength integer)
language sql stable security definer set search_path = '' as $$
  with final_cards as (
    select p.user_id, r.slot,
           case when d.replace_slot = r.slot then x.player_id else p.player_id end as player_id,
           case when d.replace_slot = r.slot then x.season else p.season end as season,
           case when d.replace_slot = r.slot then 'X_FACTOR' else r.slot end as source_slot
      from public.sabotage_draft_picks p
      join public.sabotage_draft_rounds r on r.match_id = p.match_id and r.round_number = p.round_number
      join public.sabotage_draft_x_factor_decisions d on d.match_id = p.match_id and d.user_id = p.user_id
      join public.sabotage_draft_picks x on x.match_id = p.match_id and x.user_id = p.user_id and x.round_number = 14
     where p.match_id = p_match_id and p.round_number between 1 and 13
  )
  select c.user_id, sum(pool.av)::integer
    from final_cards c
    join public.sabotage_draft_rounds source_round
      on source_round.match_id = p_match_id
     and source_round.round_number = case when c.source_slot = 'X_FACTOR' then 14 else
       (select r2.round_number from public.sabotage_draft_rounds r2
         where r2.match_id = p_match_id and r2.slot = c.source_slot) end
    join private.av_roster_players pool
      on pool.franchise_code = source_round.franchise_code
     and pool.player_id = c.player_id and pool.season = c.season
     and pool.slot_category = any(sabotage_draft_private.pool_categories(source_round.slot))
   group by c.user_id;
$$;

create function sabotage_draft_private.break_record_tie(
  p_match_id uuid, p_wins smallint, p_players uuid[]
)
returns table (user_id uuid, tiebreak_rank smallint)
language plpgsql security definer set search_path = '' as $$
declare
  v_remaining uuid[] := p_players; v_next uuid[]; v_a uuid; v_b uuid;
  v_round smallint := 1; v_game smallint; v_i int; v_rank smallint := array_length(p_players, 1);
  v_strength_a integer; v_strength_b integer; v_winner uuid;
begin
  while array_length(v_remaining, 1) > 1 loop
    select array_agg(u.user_id order by random()) into v_remaining
      from unnest(v_remaining) as u(user_id);
    v_next := array[]::uuid[]; v_game := 0;
    for v_i in 1 .. array_length(v_remaining, 1) by 2 loop
      v_game := v_game + 1; v_a := v_remaining[v_i]; v_b := v_remaining[v_i + 1];
      if v_b is null then
        v_winner := v_a;
      else
        select s.roster_strength into v_strength_a from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_a;
        select s.roster_strength into v_strength_b from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_b;
        v_winner := case when random() < sabotage_draft_private.win_probability(v_strength_a, v_strength_b) then v_a else v_b end;
      end if;
      insert into public.sabotage_draft_tiebreak_games
        (match_id, record_wins, bracket_round, game_number, player_a, player_b, winner_user_id)
      values (p_match_id, p_wins, v_round, v_game, v_a, v_b, v_winner);
      v_next := array_append(v_next, v_winner);
    end loop;
    -- Everyone eliminated in this layer shares its next rank.  The winner is
    -- overwritten by a better rank on a later layer (ultimately rank 1).
    update public.sabotage_draft_standings s set tiebreak_rank = v_rank
     where s.match_id = p_match_id and s.user_id = any(v_remaining) and s.user_id <> all(v_next);
    v_remaining := v_next; v_rank := v_rank - array_length(v_next, 1); v_round := v_round + 1;
  end loop;
  update public.sabotage_draft_standings s set tiebreak_rank = 1
   where s.match_id = p_match_id and s.user_id = v_remaining[1];
  return query select s.user_id, s.tiebreak_rank from public.sabotage_draft_standings s
   where s.match_id = p_match_id and s.user_id = any(p_players);
end;
$$;

create function sabotage_draft_private.simulate_season(p_match_id uuid, p_seed double precision default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_seed double precision; v_mean integer; v_player record; v_game int; v_wins smallint;
  v_tie record;
begin
  select coalesce(p_seed, b.seed) into v_seed from sabotage_draft_private.boards b where b.match_id = p_match_id;
  if v_seed is null then raise exception 'board_not_found' using errcode = 'P0001'; end if;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  select round(avg(roster_strength))::integer into v_mean from sabotage_draft_private.roster_strengths(p_match_id);
  if v_mean is null then raise exception 'incomplete_roster' using errcode = 'P0001'; end if;
  for v_player in select * from sabotage_draft_private.roster_strengths(p_match_id) order by user_id loop
    v_wins := 0;
    for v_game in 1 .. 17 loop
      if random() < sabotage_draft_private.win_probability(v_player.roster_strength, v_mean) then v_wins := v_wins + 1; end if;
    end loop;
    insert into public.sabotage_draft_standings (match_id, user_id, roster_strength, wins, losses, tiebreak_rank)
    values (p_match_id, v_player.user_id, v_player.roster_strength, v_wins, 17 - v_wins, 1);
  end loop;
  insert into sabotage_draft_private.seasons (match_id, seed) values (p_match_id, v_seed);
  for v_tie in select wins, array_agg(user_id order by user_id) as players
                  from public.sabotage_draft_standings where match_id = p_match_id
                 group by wins having count(*) > 1 loop
    perform sabotage_draft_private.break_record_tie(p_match_id, v_tie.wins, v_tie.players);
  end loop;
  perform private.finish_match(p_match_id, (
    select jsonb_object_agg(user_id::text, (wins * 1000 + (100 - tiebreak_rank))::numeric)
      from public.sabotage_draft_standings where match_id = p_match_id
  ));
end;
$$;

create function sabotage_draft_private.maybe_complete(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.sabotage_draft_x_factor_decisions where match_id = p_match_id)
     = (select count(*) from public.sabotage_draft_players where match_id = p_match_id) then
    perform sabotage_draft_private.simulate_season(p_match_id, null);
  end if;
end;
$$;

-- Complete the already-final X-Factor transaction only when the last player
-- decides.  This keeps disconnected seats in the normal path: their timeout
-- picks and eventual X-Factor decision produce a roster like anyone else's.
create or replace function sabotage_draft.submit_x_factor_decision(
  p_match_id uuid, p_replace_slot text default null
)
returns public.sabotage_draft_x_factor_decisions
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_board public.sabotage_draft_matches; v_decision public.sabotage_draft_x_factor_decisions;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_board.current_round <> 14 or not v_board.x_factor_open or v_board.pick_deadline is not null or v_board.guess_deadline is not null then raise exception 'x_factor_not_ready' using errcode = 'P0001'; end if;
  if exists (select 1 from public.sabotage_draft_x_factor_decisions where match_id = p_match_id and user_id = v_user) then raise exception 'x_factor_already_decided' using errcode = 'P0001'; end if;
  if p_replace_slot is not null and p_replace_slot not in ('QB','RB1','RB2','WR1','WR2','WR3','TE') then raise exception 'invalid_x_factor_slot' using errcode = 'P0001'; end if;
  if p_replace_slot is not null and not exists (select 1 from public.sabotage_draft_picks p join public.sabotage_draft_rounds r on r.match_id=p.match_id and r.round_number=p.round_number where p.match_id=p_match_id and p.user_id=v_user and r.slot=p_replace_slot and p.round_number between 1 and 13) then raise exception 'x_factor_slot_unavailable' using errcode = 'P0001'; end if;
  insert into public.sabotage_draft_x_factor_decisions (match_id, user_id, replace_slot) values (p_match_id, v_user, p_replace_slot) returning * into v_decision;
  perform sabotage_draft_private.maybe_complete(p_match_id);
  return v_decision;
end;
$$;

alter table public.sabotage_draft_standings enable row level security;
alter table public.sabotage_draft_tiebreak_games enable row level security;
create policy sabotage_draft_standings_select_member on public.sabotage_draft_standings for select to authenticated using (private.is_match_member(match_id));
create policy sabotage_draft_tiebreak_games_select_member on public.sabotage_draft_tiebreak_games for select to authenticated using (private.is_match_member(match_id));
grant select on public.sabotage_draft_standings, public.sabotage_draft_tiebreak_games to authenticated;
alter publication supabase_realtime add table public.sabotage_draft_standings;
alter publication supabase_realtime add table public.sabotage_draft_tiebreak_games;
revoke all on function sabotage_draft_private.win_probability(integer, integer), sabotage_draft_private.roster_strengths(uuid), sabotage_draft_private.break_record_tie(uuid, smallint, uuid[]), sabotage_draft_private.simulate_season(uuid, double precision), sabotage_draft_private.maybe_complete(uuid) from public, anon, authenticated;
