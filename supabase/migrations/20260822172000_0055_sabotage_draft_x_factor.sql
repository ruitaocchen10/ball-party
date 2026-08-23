-- Sabotage draft: round fourteen's private, post-guess X-Factor decision.
--
-- The round's card is still an ordinary pick: 0051 widened X_FACTOR's pool,
-- and 0052/0053 submit, hide, and settle it exactly as they do every other
-- round.  This file deliberately begins only after that shared guess window
-- has closed.  A player may then either name one of their seven existing
-- offensive-skill slots for the X-Factor card to replace, or record NULL to
-- discard the card.  There is no target argument and no guess-shaped write,
-- so this decision cannot become another sabotage opportunity.

alter table public.sabotage_draft_matches
  add column x_factor_open boolean not null default false;

alter type sabotage_draft.round add attribute x_factor_open boolean;

-- The decision is the final roster-state overlay: NULL means the round-14
-- card is discarded; a named slot means it replaces that round's original
-- card when the scorer assembles the roster.  Keeping the source cards in
-- sabotage_draft_picks immutable means exact guesses and normal picks retain
-- one uniform history for #43 to score.
create table public.sabotage_draft_x_factor_decisions (
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null,
  replace_slot text,
  created_at timestamptz not null default now(),

  primary key (match_id, user_id),
  foreign key (match_id, user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  check (replace_slot is null or replace_slot in ('QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE'))
);

create or replace function sabotage_draft_private.round_of(p_match_id uuid)
returns sabotage_draft.round
language sql stable security definer set search_path = '' as $$
  select (m.match_id, m.round_count, m.current_round, r.slot, r.franchise_code,
          m.pick_deadline, now(), m.guess_deadline, m.x_factor_open)::sabotage_draft.round
    from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r
      on r.match_id = m.match_id and r.round_number = m.current_round
   where m.match_id = p_match_id;
$$;

-- Preserve 0053's normal advancement for rounds 1-13.  Only the final
-- transition changes: closing its ordinary guess window opens the X-Factor
-- decision phase instead of ending the match or opening another guess phase.
create or replace function sabotage_draft_private.advance_round(p_match_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_round smallint;
begin
  select current_round into v_round
    from public.sabotage_draft_matches where match_id = p_match_id;

  if v_round < 14 then
    update public.sabotage_draft_matches
       set current_round = v_round + 1,
           pick_deadline = now() + interval '45 seconds',
           guess_deadline = null,
           x_factor_open = false
     where match_id = p_match_id;
  else
    update public.sabotage_draft_matches
       set pick_deadline = null,
           guess_deadline = null,
           x_factor_open = true
     where match_id = p_match_id;
  end if;
end;
$$;

create function sabotage_draft.submit_x_factor_decision(
  p_match_id uuid,
  p_replace_slot text default null
)
returns public.sabotage_draft_x_factor_decisions
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_board public.sabotage_draft_matches;
  v_decision public.sabotage_draft_x_factor_decisions;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select sm.* into v_board
    from public.sabotage_draft_matches sm
    join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of sm;
  if not found then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.sabotage_draft_players
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_board.current_round <> 14
     or not v_board.x_factor_open
     or v_board.pick_deadline is not null
     or v_board.guess_deadline is not null then
    raise exception 'x_factor_not_ready' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.sabotage_draft_x_factor_decisions
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'x_factor_already_decided' using errcode = 'P0001';
  end if;

  if p_replace_slot is not null then
    if p_replace_slot not in ('QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE') then
      raise exception 'invalid_x_factor_slot' using errcode = 'P0001';
    end if;

    -- Every named destination must be a genuine existing skill slot from
    -- this player's first thirteen rounds; the X-Factor cannot add a slot.
    if not exists (
      select 1
        from public.sabotage_draft_picks p
        join public.sabotage_draft_rounds r
          on r.match_id = p.match_id and r.round_number = p.round_number
       where p.match_id = p_match_id
         and p.user_id = v_user
         and r.slot = p_replace_slot
         and p.round_number between 1 and 13
    ) then
      raise exception 'x_factor_slot_unavailable' using errcode = 'P0001';
    end if;
  end if;

  -- p_replace_slot = NULL is the explicit discard option.
  insert into public.sabotage_draft_x_factor_decisions (match_id, user_id, replace_slot)
  values (p_match_id, v_user, p_replace_slot)
  returning * into v_decision;

  return v_decision;
end;
$$;

alter table public.sabotage_draft_x_factor_decisions enable row level security;
create policy sabotage_draft_x_factor_decisions_select_member
  on public.sabotage_draft_x_factor_decisions
  for select to authenticated using (private.is_match_member(match_id));
grant select on public.sabotage_draft_x_factor_decisions to authenticated;
alter publication supabase_realtime add table public.sabotage_draft_x_factor_decisions;

revoke all on function sabotage_draft.submit_x_factor_decision(uuid, text) from public, anon;
grant execute on function sabotage_draft.submit_x_factor_decision(uuid, text) to authenticated;
