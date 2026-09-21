-- QB Season Builder: never show a team-season twice in one run.
--
-- A spin is part of what the player experienced, including a spin replaced by
-- the one available respin. Subsequent draws therefore exclude every stored
-- spin for the match, rather than only the spin currently in play.

create function qb_season_builder_private.draw_spin(p_match_id uuid)
returns table (franchise_code text, season smallint)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return query
    select q.franchise_code, q.season
      from (
        select distinct s.franchise_code, s.season
          from qb_season_builder_private.qb_seasons s
      ) q
     where not exists (
       select 1
         from public.qb_season_builder_spins shown
        where shown.match_id = p_match_id
          and shown.franchise_code = q.franchise_code
          and shown.season = q.season
     )
     order by random()
     limit 1;

  if not found then
    raise exception 'pool_exhausted' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function qb_season_builder.start(p_match_id uuid, p_mode text default 'visible')
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
  v_spin  record;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_mode is null or p_mode not in ('visible', 'hidden') then
    raise exception 'invalid_mode' using errcode = '22023';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_match.game <> 'qb_season_builder' then
    raise exception 'wrong_game' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.run_participants
     where run_id = v_match.run_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_match.status <> 'setup'::public.match_status then
    raise exception 'match_not_setup' using errcode = 'P0001';
  end if;

  insert into public.qb_season_builder_matches (match_id, mode)
  values (p_match_id, p_mode);

  select * into v_spin from qb_season_builder_private.draw_spin(p_match_id);
  insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
  values (p_match_id, 1, 1, v_spin.franchise_code, v_spin.season);

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  return qb_season_builder_private.board_of(p_match_id);
end;
$$;

create or replace function qb_season_builder.pick(
  p_match_id uuid,
  p_slot text,
  p_player_id text default null
)
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_run   public.qb_season_builder_matches;
  v_spin  public.qb_season_builder_spins;
  v_qb    qb_season_builder_private.qb_seasons;
  v_value smallint;
  v_next  record;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_slot is null
     or p_slot not in ('accuracy', 'arm_talent', 'mobility', 'iq', 'build', 'supporting_cast') then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;

  v_run := qb_season_builder_private.lock_playing_run(p_match_id, v_user);

  if v_run.drafted_at is not null then
    raise exception 'draft_complete' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.qb_season_builder_picks p
     where p.match_id = p_match_id and p.slot = p_slot
  ) then
    raise exception 'slot_filled' using errcode = 'P0001';
  end if;

  if (p_slot = 'supporting_cast') <> (p_player_id is null) then
    raise exception 'invalid_source' using errcode = '22023';
  end if;

  v_spin := qb_season_builder_private.current_spin_of(p_match_id, v_run.current_round);

  if p_slot = 'supporting_cast' then
    select t.supporting_cast into v_value
      from qb_season_builder_private.team_seasons t
     where t.franchise_code = v_spin.franchise_code and t.season = v_spin.season;
  else
    select * into v_qb
      from qb_season_builder_private.qb_seasons q
     where q.franchise_code = v_spin.franchise_code
       and q.season = v_spin.season
       and q.player_id = p_player_id;

    if not found then
      raise exception 'source_not_on_spin' using errcode = 'P0001';
    end if;

    v_value := case p_slot
      when 'accuracy'   then v_qb.accuracy
      when 'arm_talent' then v_qb.arm_talent
      when 'mobility'   then v_qb.mobility
      when 'iq'         then v_qb.iq
      when 'build'      then v_qb.build
    end;
  end if;

  insert into public.qb_season_builder_picks (
    match_id, round_number, slot, franchise_code, season, player_id, display_name
  )
  values (
    p_match_id, v_run.current_round, p_slot, v_spin.franchise_code, v_spin.season,
    p_player_id, v_qb.display_name
  );

  insert into qb_season_builder_private.pick_values (match_id, slot, value)
  values (p_match_id, p_slot, v_value);

  if v_run.current_round < v_run.round_count then
    select * into v_next from qb_season_builder_private.draw_spin(p_match_id);

    insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
    values (p_match_id, v_run.current_round + 1, 1, v_next.franchise_code, v_next.season);

    update public.qb_season_builder_matches
       set current_round = current_round + 1
     where match_id = p_match_id;
  else
    update public.qb_season_builder_matches
       set drafted_at = now()
     where match_id = p_match_id;
  end if;

  return qb_season_builder_private.board_of(p_match_id);
end;
$$;

create or replace function qb_season_builder.respin(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_run   public.qb_season_builder_matches;
  v_spin  public.qb_season_builder_spins;
  v_next  record;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_run := qb_season_builder_private.lock_playing_run(p_match_id, v_user);

  if v_run.drafted_at is not null then
    raise exception 'draft_complete' using errcode = 'P0001';
  end if;

  if v_run.respin_used then
    raise exception 'respin_used' using errcode = 'P0001';
  end if;

  v_spin := qb_season_builder_private.current_spin_of(p_match_id, v_run.current_round);

  select * into v_next from qb_season_builder_private.draw_spin(p_match_id);

  insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
  values (p_match_id, v_run.current_round, 2, v_next.franchise_code, v_next.season);

  update public.qb_season_builder_matches
     set respin_used = true
   where match_id = p_match_id;

  return qb_season_builder_private.board_of(p_match_id);
end;
$$;

revoke all on function qb_season_builder_private.draw_spin(uuid)
  from public, anon, authenticated;
drop function qb_season_builder_private.draw_spin(text, smallint);
