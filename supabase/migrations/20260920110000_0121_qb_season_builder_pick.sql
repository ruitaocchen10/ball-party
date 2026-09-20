-- QB Season Builder: picking a source into an open slot, and advancing rounds.
-- See issue #74. The deal and the state read are 0120; the respin is 0122.
--
-- A pick names ONE OPEN SLOT and ONE SOURCE on the current spin. The six slots
-- are the six values a quarterback is built from, and each is filled exactly
-- once:
--
--   accuracy, arm_talent, mobility, iq, build
--                   taken from a quarterback on the spin — the slot IS the
--                   quality, so the pick names the quarterback (p_player_id)
--   supporting_cast the team's Supporting Cast; there is no quarterback, so
--                   p_player_id must be null
--
-- "The player chooses which open slot a spin fills" is therefore the pick
-- itself: the same spin can fill any open slot it can supply, and taking one
-- leaves the rest for a later spin.
--
-- Picking closes the round. Round N+1's spin is dealt in the same transaction,
-- so the run is never between rounds; after the sixth pick there is no round to
-- open and the run is marked drafted, ready to finish.
--
-- The value a pick was worth is copied into a private table at pick time
-- rather than looked up again later. The ratings are reloaded by the pipeline,
-- and a run in flight must keep the number it was shown (visible) or promised
-- (hidden) when it picked. It is private for the same reason the ratings are —
-- see 0120's header: a hidden run's numbers must not sit in a table a client
-- can select from.

create table public.qb_season_builder_picks (
  match_id       uuid     not null references public.matches (id) on delete cascade,
  round_number   smallint not null check (round_number between 1 and 6),
  slot           text     not null check (slot in (
                   'accuracy', 'arm_talent', 'mobility', 'iq', 'build', 'supporting_cast'
                 )),
  franchise_code text     not null,
  season         smallint not null,
  -- The quarterback, when the source was one. The Supporting Cast has none.
  player_id      text,
  display_name   text,

  primary key (match_id, slot),
  unique (match_id, round_number),
  check ((slot = 'supporting_cast') = (player_id is null))
);

create table qb_season_builder_private.pick_values (
  match_id uuid     not null,
  slot     text     not null,
  value    smallint not null check (value between 0 and 99),

  primary key (match_id, slot),
  foreign key (match_id, slot)
    references public.qb_season_builder_picks (match_id, slot) on delete cascade
);

alter table qb_season_builder_private.pick_values enable row level security;
revoke all on table qb_season_builder_private.pick_values from public, anon, authenticated;

alter table public.qb_season_builder_picks enable row level security;
create policy qb_season_builder_picks_select_member on public.qb_season_builder_picks
  for select to authenticated using (private.is_match_member(match_id));
grant select on public.qb_season_builder_picks to authenticated;

-- ------------------------------------------------------------ the projection --

-- 0120's projection with the picks filled in. Rebuilt in full rather than
-- patched: it is one function and the whole of it is the point.
create or replace function qb_season_builder_private.board_of(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
-- Volatile on purpose: pick and respin call it after writing in the same
-- transaction and need it to see those writes, which a STABLE function only
-- does by the accident of taking a fresh snapshot per call.
security definer
set search_path = ''
as $$
declare
  v_run     public.qb_season_builder_matches;
  v_spin    public.qb_season_builder_spins;
  v_reveal  boolean;
  v_options jsonb;
  v_picks   jsonb;
begin
  select * into v_run from public.qb_season_builder_matches where match_id = p_match_id;
  if not found then
    raise exception 'match_not_started' using errcode = 'P0002';
  end if;

  v_reveal := v_run.mode = 'visible'
    or exists (
      select 1 from public.matches m
       where m.id = p_match_id and m.status = 'complete'::public.match_status
    );

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'round',          p.round_number,
             'slot',           p.slot,
             'franchise_code', p.franchise_code,
             'season',         p.season,
             'player_id',      p.player_id,
             'display_name',   p.display_name,
             'value',          case when v_reveal then pv.value end
           )
           order by p.round_number
         ), '[]'::jsonb)
    into v_picks
    from public.qb_season_builder_picks p
    join qb_season_builder_private.pick_values pv
      on pv.match_id = p.match_id and pv.slot = p.slot
   where p.match_id = p_match_id;

  if v_run.drafted_at is null then
    v_spin := qb_season_builder_private.current_spin_of(p_match_id, v_run.current_round);
    v_options := qb_season_builder_private.options_of(v_spin.franchise_code, v_spin.season, v_reveal);
  end if;

  return (
    v_run.match_id,
    v_run.mode,
    case when v_run.drafted_at is null then 'picking' else 'ready_to_finish' end,
    v_run.round_count,
    v_run.current_round,
    v_run.respin_used,
    v_spin.franchise_code,
    v_spin.season,
    v_options,
    v_picks
  )::qb_season_builder.board;
end;
$$;

-- --------------------------------------------------------------- the pick --

-- Errors are the contract with the client, matched by message:
--   not_authenticated     no session
--   invalid_slot          not one of the six                       (22023)
--   invalid_source        the source's shape does not fit the slot (22023)
--   match_not_found       no such match                            (P0002)
--   wrong_game            the match belongs to another game
--   not_a_participant     not this run's player
--   match_not_playing     the run has not been dealt (or is over)
--   draft_complete        every slot is already filled
--   slot_filled           that slot already has its pick
--   source_not_on_spin    the quarterback is not on the current spin
create function qb_season_builder.pick(
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

  -- Picking closes the round. Open the next one, or mark the draft finished.
  if v_run.current_round < v_run.round_count then
    select * into v_next from qb_season_builder_private.draw_spin();

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

revoke all on function qb_season_builder.pick(uuid, text, text) from public, anon;
grant execute on function qb_season_builder.pick(uuid, text, text) to authenticated;
