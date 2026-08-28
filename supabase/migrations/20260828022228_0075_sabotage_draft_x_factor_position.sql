-- An X-Factor upgrades a roster slot of its own position; it cannot turn a
-- player drafted at one position into a replacement for another position.
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
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  if v_user <> v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;
  if v_board.current_round <> 14 or not v_board.x_factor_open or v_board.turn_deadline is not null then raise exception 'x_factor_not_ready' using errcode = 'P0001'; end if;
  if exists (select 1 from public.sabotage_draft_x_factor_decisions where match_id = p_match_id and user_id = v_user) then raise exception 'x_factor_already_decided' using errcode = 'P0001'; end if;

  if p_replace_slot is not null then
    if p_replace_slot not in ('QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE') then raise exception 'invalid_x_factor_slot' using errcode = 'P0001'; end if;

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
  values (p_match_id, v_user, p_replace_slot)
  returning * into v_decision;

  v_count := sabotage_draft_private.player_count(p_match_id);
  if v_board.active_seat < v_count - 1 then
    update public.sabotage_draft_matches set active_seat = v_board.active_seat + 1, x_factor_open = false, turn_deadline = now() + interval '45 seconds' where match_id = p_match_id;
  else
    perform sabotage_draft_private.maybe_complete(p_match_id);
  end if;
  return v_decision;
end;
$$;
