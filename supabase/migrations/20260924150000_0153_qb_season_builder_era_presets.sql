-- QB Season Builder: three era presets a run can be started in, so a player who
-- only knows the modern game can leave the 2000s out of the pool and vice versa.
--
-- `all` (2006-2025, the whole pool every run before this migration dealt from),
-- `classic` (2006-2015) and `modern` (2016-2025), an even split of the ratings
-- pipeline's twenty seasons (docs/games/qb_season_builder.md). Chosen at start,
-- like mode, and locked for the run the same way: there is no call that changes
-- it afterwards.
--
-- draw_spin (0128) already excludes every team-season the run has shown, across
-- rounds and the respin alike ("never show a team-season twice in one run"), so
-- narrowing its pool to an era is the same kind of risk the auction's free
-- season_from/season_to already carries (0030_auction_season_range.sql) and not
-- a new one: a run needs at most round_count + 1 (7) distinct team-seasons, and
-- either ten-season preset offers roughly thirty times that many before the
-- qualifying-quarterback filter even applies. Unlike the auction, this makes no
-- claim about a minimum span — these presets aren't a free range, and both of
-- them are comfortably wide. pool_exhausted stays reachable only the way it
-- already was: an era with no qualifying team-season left to show, a
-- pipeline-data problem rather than a player's choice of window.
--
-- WHY PRESETS AND NOT A FREE RANGE: considered and written up for the user
-- alongside the auction's precedent (issue discussion, 2026-09-24). A free range
-- would need its own resolver and a two-ended picker; three presets are a
-- segmented control and one enum column, and nothing about shipping presets
-- forecloses widening to a free range later if it turns out to matter.

-- ------------------------------------------------------------------- the era --

-- The season window each preset deals from. A SQL function, not a table: the
-- three presets are fixed copy a client hardcodes (as it already does for mode's
-- "Visible"/"Hidden"), so there is nothing here for a picker to read at runtime,
-- unlike the auction's data-driven auction.season_bounds().
create function qb_season_builder_private.era_bounds(
  p_era text,
  out min_season smallint,
  out max_season smallint
)
language sql
immutable
set search_path = ''
as $$
  select (case p_era when 'all' then 2006 when 'classic' then 2006 when 'modern' then 2016 end)::smallint,
         (case p_era when 'all' then 2025 when 'classic' then 2015 when 'modern' then 2025 end)::smallint
$$;

revoke all on function qb_season_builder_private.era_bounds(text) from public, anon, authenticated;

-- The run's own choice, alongside mode. Rows dealt before this migration were
-- all dealt from the whole pool, so 'all' is not a default standing in for the
-- truth of those rows — it is the truth, same reasoning as the auction's
-- season_from/season_to backfill.
alter table public.qb_season_builder_matches
  add column era text not null default 'all' check (era in ('all', 'classic', 'modern'));

-- ------------------------------------------------------------------- the deal --

-- 0128's draw, narrowed to an era's window. The two new bounds are trailing
-- parameters with the whole pool as their default, so a call that names neither
-- draws exactly as 0128 did.
drop function qb_season_builder_private.draw_spin(uuid);

create function qb_season_builder_private.draw_spin(
  p_match_id   uuid,
  p_min_season smallint default 2006,
  p_max_season smallint default 2025
)
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
         where s.season between p_min_season and p_max_season
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

revoke all on function qb_season_builder_private.draw_spin(uuid, smallint, smallint)
  from public, anon, authenticated;

-- ------------------------------------------------------------ the projection --

-- Appended after 0127's `shown`, not inserted: board_of builds the tuple
-- positionally, and an appended attribute is the one change that needs no
-- reordering of the values already in it.
alter type qb_season_builder.board add attribute era text;

-- 0127's projection with the run's era in it. Rebuilt in full rather than
-- patched, as 0121 and 0127 each did before it — one function, and the whole of
-- it is the point.
create or replace function qb_season_builder_private.board_of(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
-- Volatile on purpose, as in 0121 and 0127.
security definer
set search_path = ''
as $$
declare
  v_run      public.qb_season_builder_matches;
  v_spin     public.qb_season_builder_spins;
  v_complete boolean;
  v_reveal   boolean;
  v_options  jsonb;
  v_picks    jsonb;
  v_shown    jsonb;
begin
  select * into v_run from public.qb_season_builder_matches where match_id = p_match_id;
  if not found then
    raise exception 'match_not_started' using errcode = 'P0002';
  end if;

  v_complete := exists (
    select 1 from public.matches m
     where m.id = p_match_id and m.status = 'complete'::public.match_status
  );
  v_reveal := v_run.mode = 'visible' or v_complete;

  v_picks := qb_season_builder_private.picks_of(p_match_id, v_reveal);

  if v_run.drafted_at is null then
    v_spin := qb_season_builder_private.current_spin_of(p_match_id, v_run.current_round);
    v_options := qb_season_builder_private.options_of(v_spin.franchise_code, v_spin.season, v_reveal);
  end if;

  if v_complete then
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'round',          s.round_number,
               'attempt',        s.attempt,
               'franchise_code', s.franchise_code,
               'season',         s.season,
               'options',        qb_season_builder_private.options_of(s.franchise_code, s.season, true)
             )
             order by s.round_number, s.attempt
           ), '[]'::jsonb)
      into v_shown
      from public.qb_season_builder_spins s
     where s.match_id = p_match_id;
  end if;

  return (
    v_run.match_id,
    v_run.mode,
    case when v_complete then 'complete'
         when v_run.drafted_at is null then 'picking'
         else 'ready_to_finish' end,
    v_run.round_count,
    v_run.current_round,
    v_run.respin_used,
    v_spin.franchise_code,
    v_spin.season,
    v_options,
    v_picks,
    v_shown,
    v_run.era
  )::qb_season_builder.board;
end;
$$;

-- ------------------------------------------------------------------- start --

drop function qb_season_builder.start(uuid, text);

create function qb_season_builder.start(p_match_id uuid, p_mode text default 'visible', p_era text default 'all')
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_match  public.matches;
  v_bounds record;
  v_spin   record;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_mode is null or p_mode not in ('visible', 'hidden') then
    raise exception 'invalid_mode' using errcode = '22023';
  end if;

  if p_era is null or p_era not in ('all', 'classic', 'modern') then
    raise exception 'invalid_era' using errcode = '22023';
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

  insert into public.qb_season_builder_matches (match_id, mode, era)
  values (p_match_id, p_mode, p_era);

  select * into v_bounds from qb_season_builder_private.era_bounds(p_era);
  select * into v_spin from qb_season_builder_private.draw_spin(
    p_match_id, v_bounds.min_season, v_bounds.max_season
  );
  insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
  values (p_match_id, 1, 1, v_spin.franchise_code, v_spin.season);

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  return qb_season_builder_private.board_of(p_match_id);
end;
$$;

revoke all on function qb_season_builder.start(uuid, text, text) from public, anon;
grant execute on function qb_season_builder.start(uuid, text, text) to authenticated;

-- -------------------------------------------------------------------- pick --

-- Same signature and same rules as 0128; only the deal at the end narrows to
-- the run's own era instead of the whole pool.
create or replace function qb_season_builder.pick(
  p_match_id  uuid,
  p_slot      text,
  p_player_id text default null
)
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_run    public.qb_season_builder_matches;
  v_spin   public.qb_season_builder_spins;
  v_qb     qb_season_builder_private.qb_seasons;
  v_value  smallint;
  v_bounds record;
  v_next   record;
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
    select * into v_bounds from qb_season_builder_private.era_bounds(v_run.era);
    select * into v_next from qb_season_builder_private.draw_spin(
      p_match_id, v_bounds.min_season, v_bounds.max_season
    );

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

-- ------------------------------------------------------------------- respin --

-- Same signature and same rules as 0128; the reroll is drawn from the run's own
-- era instead of the whole pool.
create or replace function qb_season_builder.respin(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_run    public.qb_season_builder_matches;
  v_spin   public.qb_season_builder_spins;
  v_bounds record;
  v_next   record;
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

  select * into v_bounds from qb_season_builder_private.era_bounds(v_run.era);
  select * into v_next from qb_season_builder_private.draw_spin(
    p_match_id, v_bounds.min_season, v_bounds.max_season
  );

  insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
  values (p_match_id, v_run.current_round, 2, v_next.franchise_code, v_next.season);

  update public.qb_season_builder_matches
     set respin_used = true
   where match_id = p_match_id;

  return qb_season_builder_private.board_of(p_match_id);
end;
$$;
