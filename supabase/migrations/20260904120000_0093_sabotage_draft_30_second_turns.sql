-- Every path that opens a sabotage turn uses the same 30-second window:
-- initial deal, ordinary turn advancement, and the next seat after an
-- X-Factor decision. Keep the duration server-authoritative; the client only
-- mirrors it for its countdown animation.

create or replace function sabotage_draft_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seed  double precision := coalesce(p_seed, random());
  v_n     int;
  v_i     smallint;
  v_slot  text;
  v_franchise text;
  v_player record;
  v_slots constant text[] := array[
    'QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE',
    'OL', 'DL', 'LB', 'CB', 'S', 'ST'
  ];
begin
  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  insert into public.sabotage_draft_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  select count(*) into v_n from public.sabotage_draft_players where match_id = p_match_id;
  if v_n < 2 then raise exception 'too_few_players' using errcode = 'P0001'; end if;

  for v_i in 1 .. 14 loop
    v_slot := case when v_i <= 13 then v_slots[v_i] else 'X_FACTOR' end;
    insert into public.sabotage_draft_rounds (match_id, round_number, slot)
    values (p_match_id, v_i, v_slot);

    for v_player in
      select sp.user_id from public.sabotage_draft_players sp
       where sp.match_id = p_match_id order by sp.seat
    loop
      select r.franchise_code into v_franchise
        from private.av_roster_players r
       where r.slot_category = any(sabotage_draft_private.pool_categories(v_slot))
       group by r.franchise_code order by random() limit 1;
      if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
      insert into public.sabotage_draft_round_spins (match_id, round_number, user_id, franchise_code)
      values (p_match_id, v_i, v_player.user_id, v_franchise);
    end loop;
  end loop;

  insert into public.sabotage_draft_matches (match_id, round_count, current_round, active_seat, turn_deadline)
  values (p_match_id, 14, 1, 0, now() + interval '30 seconds');
  insert into sabotage_draft_private.boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

create or replace function sabotage_draft_private.advance_turn(p_match_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_round smallint; v_seat smallint; v_count smallint;
begin
  select current_round, active_seat into v_round, v_seat
    from public.sabotage_draft_matches where match_id = p_match_id;
  v_count := sabotage_draft_private.player_count(p_match_id);

  if v_round = 14 then
    update public.sabotage_draft_matches set turn_deadline = null, x_factor_open = true
     where match_id = p_match_id;
    return;
  end if;

  if v_seat < v_count - 1 then
    update public.sabotage_draft_matches
       set active_seat = v_seat + 1, turn_deadline = now() + interval '30 seconds'
     where match_id = p_match_id;
  else
    update public.sabotage_draft_matches
       set current_round = v_round + 1, active_seat = 0, turn_deadline = now() + interval '30 seconds'
     where match_id = p_match_id;
  end if;
end;
$$;

create or replace function sabotage_draft.submit_x_factor_decision(
  p_match_id uuid, p_replace_slot text default null
)
returns public.sabotage_draft_x_factor_decisions
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches;
  v_active uuid; v_count smallint; v_decision public.sabotage_draft_x_factor_decisions;
  v_category text;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  if v_user <> v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;
  if v_board.current_round <> 14 or not v_board.x_factor_open or v_board.turn_deadline is not null then
    raise exception 'x_factor_not_ready' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.sabotage_draft_x_factor_decisions where match_id = p_match_id and user_id = v_user) then
    raise exception 'x_factor_already_decided' using errcode = 'P0001';
  end if;

  if p_replace_slot is not null then
    if p_replace_slot not in ('QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE') then
      raise exception 'invalid_x_factor_slot' using errcode = 'P0001';
    end if;
    select pool.slot_category into v_category
      from public.sabotage_draft_picks pick
      join public.sabotage_draft_round_spins spin on spin.match_id = pick.match_id and spin.round_number = pick.round_number and spin.user_id = pick.user_id
      join private.av_roster_players pool on pool.franchise_code = spin.franchise_code and pool.player_id = pick.player_id and pool.season = pick.season
     where pick.match_id = p_match_id and pick.user_id = v_user and pick.round_number = 14;
    if not found then raise exception 'x_factor_pick_unavailable' using errcode = 'P0001'; end if;
    if not ((v_category = 'QB' and p_replace_slot = 'QB') or (v_category = 'RB' and p_replace_slot in ('RB1', 'RB2')) or (v_category = 'WR' and p_replace_slot in ('WR1', 'WR2', 'WR3')) or (v_category = 'TE' and p_replace_slot = 'TE')) then
      raise exception 'x_factor_position_mismatch' using errcode = 'P0001';
    end if;
  end if;

  insert into public.sabotage_draft_x_factor_decisions (match_id, user_id, replace_slot)
  values (p_match_id, v_user, p_replace_slot) returning * into v_decision;

  v_count := sabotage_draft_private.player_count(p_match_id);
  if v_board.active_seat < v_count - 1 then
    update public.sabotage_draft_matches
       set active_seat = v_board.active_seat + 1, x_factor_open = false,
           turn_deadline = now() + interval '30 seconds'
     where match_id = p_match_id;
  else
    perform sabotage_draft_private.maybe_complete(p_match_id);
  end if;
  return v_decision;
end;
$$;
