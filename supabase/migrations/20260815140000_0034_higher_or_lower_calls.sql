-- A call is a private decision until its owner has committed.  The direction
-- therefore lives on a row whose SELECT policy is itself part of the game
-- rule; the separate presence projection lets the table show lock-ins without
-- turning a hidden direction into a nullable public column.

create table public.higher_or_lower_calls (
  match_id   uuid not null references public.matches (id) on delete cascade,
  question   smallint not null check (question > 0),
  user_id    uuid not null references public.profiles (id),
  direction  text not null check (direction in ('higher', 'lower')),
  created_at timestamptz not null default now(),

  primary key (match_id, question, user_id),
  foreign key (match_id, user_id)
    references public.higher_or_lower_players (match_id, user_id) on delete cascade
);

-- Presence is intentionally not a projection of calls. A participant may
-- always read this table, whereas the call row remains direction-sensitive.
create table public.higher_or_lower_call_statuses (
  match_id uuid not null references public.matches (id) on delete cascade,
  question smallint not null check (question > 0),
  user_id uuid not null references public.profiles (id),
  primary key (match_id, question, user_id),
  foreign key (match_id, user_id)
    references public.higher_or_lower_players (match_id, user_id) on delete cascade
);

alter table public.higher_or_lower_players
  add column current_streak integer not null default 0 check (current_streak >= 0),
  add column best_streak integer not null default 0 check (best_streak >= 0),
  add column correct_count integer not null default 0 check (correct_count >= 0);

-- A policy on calls cannot ask calls whether the viewer has called: that
-- recurses through RLS. This narrowly-scoped definer helper asks the question
-- below the policy, and takes the viewer explicitly so it is usable for the
-- row being evaluated as well as the caller's own row.
create function higher_or_lower_private.has_called(
  p_match_id uuid,
  p_question smallint,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.higher_or_lower_calls
     where match_id = p_match_id and question = p_question and user_id = p_user_id
  );
$$;

create function higher_or_lower.call(p_match_id uuid, p_direction text)
returns public.higher_or_lower_calls
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_board public.higher_or_lower_matches;
  v_call public.higher_or_lower_calls;
  v_correct boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_direction not in ('higher', 'lower') then
    raise exception 'invalid_direction' using errcode = 'P0001';
  end if;

  -- One match-row lock serializes both deadline validation and a player's
  -- duplicate call. The second transaction sees the first one's row only
  -- after it has committed, so no unique-violation race leaks through.
  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of hm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (
    select 1 from public.higher_or_lower_players
     where match_id = p_match_id and user_id = v_user
  ) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_board.phase <> 'call' then raise exception 'call_not_open' using errcode = 'P0001'; end if;
  if v_board.phase_deadline is null or v_board.phase_deadline <= now() then
    raise exception 'call_deadline_passed' using errcode = 'P0001';
  end if;
  if higher_or_lower_private.has_called(p_match_id, v_board.current_question, v_user) then
    raise exception 'already_called' using errcode = 'P0001';
  end if;

  insert into public.higher_or_lower_calls (match_id, question, user_id, direction)
  values (p_match_id, v_board.current_question, v_user, p_direction)
  returning * into v_call;

  insert into public.higher_or_lower_call_statuses (match_id, question, user_id)
  values (p_match_id, v_board.current_question, v_user);

  select case
    when challenger.points > anchor.points then p_direction = 'higher'
    else p_direction = 'lower'
  end into v_correct
    from higher_or_lower_private.answers anchor
    join higher_or_lower_private.answers challenger
      on challenger.match_id = anchor.match_id
     and challenger.ordinal = anchor.ordinal + 1
   where anchor.match_id = p_match_id
     and anchor.ordinal = v_board.current_question - 1;

  update public.higher_or_lower_players
     set current_streak = case when v_correct then current_streak + 1 else 0 end,
         best_streak = case when v_correct then greatest(best_streak, current_streak + 1) else best_streak end,
         correct_count = correct_count + case when v_correct then 1 else 0 end
   where match_id = p_match_id and user_id = v_user;

  return v_call;
end;
$$;

alter table public.higher_or_lower_calls enable row level security;
alter table public.higher_or_lower_call_statuses enable row level security;

create policy higher_or_lower_calls_select_visible on public.higher_or_lower_calls
  for select to authenticated using (
    user_id = auth.uid()
    or higher_or_lower_private.has_called(match_id, question, auth.uid())
    or exists (
      select 1 from public.higher_or_lower_cards c
       where c.match_id = higher_or_lower_calls.match_id
         and c.ordinal = higher_or_lower_calls.question
         and c.revealed_at is not null
    )
  );

create policy higher_or_lower_call_statuses_select_member
  on public.higher_or_lower_call_statuses
  for select to authenticated using (private.is_match_member(match_id));

grant select on public.higher_or_lower_calls to authenticated;
grant select on public.higher_or_lower_call_statuses to authenticated;

alter publication supabase_realtime add table public.higher_or_lower_calls;
alter publication supabase_realtime add table public.higher_or_lower_call_statuses;

revoke all on function higher_or_lower_private.has_called(uuid, smallint, uuid)
  from public, anon;
grant execute on function higher_or_lower_private.has_called(uuid, smallint, uuid) to authenticated;
revoke all on function higher_or_lower.call(uuid, text) from public, anon;
grant execute on function higher_or_lower.call(uuid, text) to authenticated;
