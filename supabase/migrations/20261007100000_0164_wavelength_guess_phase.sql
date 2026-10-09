-- 2v2 Wavelength: sequential guesses, wedge scoring, and the public reveal
-- (issue #100).  The target remains in its psychic-only table; its copied
-- value on wavelength_rounds is deliberately null until the guess is locked.

alter table public.wavelength_rounds
  add column revealed_target smallint check (revealed_target between 0 and 1000);

-- A card and clue become table-visible only once their round opens.  The
-- psychic-only policies from #98/#99 still cover the fill phase.
create policy wavelength_cards_select_open_round on public.wavelength_cards
  for select to authenticated
  using (
    exists (
      select 1
        from public.wavelength_rounds r
       where r.match_id = wavelength_cards.match_id
         and r.round = wavelength_cards.round
         and r.status in ('open', 'locked', 'skipped')
         and private.is_match_member(r.match_id)
    )
  );

create policy wavelength_clues_select_open_round on public.wavelength_clues
  for select to authenticated
  using (
    exists (
      select 1
        from public.wavelength_rounds r
       where r.match_id = wavelength_clues.match_id
         and r.round = wavelength_clues.round
         and r.status in ('open', 'locked', 'skipped')
         and private.is_match_member(r.match_id)
    )
  );

-- Keep state a named projection.  `team_scores` is ordered by team number;
-- co-op has one entry and versus has entries for teams 0 and 1.
alter type wavelength.board add attribute team_scores smallint[];

create or replace function wavelength_private.board_of(p_match_id uuid)
returns wavelength.board
language sql
stable
security definer
set search_path = ''
as $$
  select (m.match_id, m.mode, m.preset, m.round_count, m.current_round,
          m.phase, m.phase_deadline, now(),
          coalesce((
            select array_agg(score order by team)
              from (
                select p.team, coalesce(sum(r.points), 0)::smallint as score
                  from public.wavelength_players p
                  left join public.wavelength_rounds r
                    on r.match_id = p.match_id
                   and r.psychic_id = p.user_id
                   and r.status in ('locked', 'skipped')
                 where p.match_id = m.match_id
                 group by p.team
              ) scores
          ), '{}'::smallint[]))::wavelength.board
    from public.wavelength_matches m
   where m.match_id = p_match_id;
$$;

-- #99 opened the first round.  Now that guessing has a clock, make that same
-- transition install the configured deadline.  Replacing the function here
-- keeps migrations immutable and lets #99 remain independently deployable.
create or replace function wavelength.submit_clue(
  p_match_id uuid,
  p_round    integer,
  p_clue     text
)
returns wavelength.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_board public.wavelength_matches;
  v_clue  text := btrim(coalesce(p_clue, ''));
  v_cfg   jsonb := wavelength_private.config();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select wm.* into v_board
    from public.wavelength_matches wm
    join public.matches m on m.id = wm.match_id
   where wm.match_id = p_match_id
     and m.status = 'playing'::public.match_status
   for update of wm;
  if not found then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.wavelength_players
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  if v_board.phase <> 'fill' then
    raise exception 'clue_not_open' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.wavelength_rounds
     where match_id = p_match_id and round = p_round and psychic_id = v_user
  ) then
    raise exception 'not_psychic' using errcode = '42501';
  end if;
  if v_clue = '' then
    raise exception 'clue_required' using errcode = 'P0001';
  end if;
  if v_clue ~ '[0-9]' then
    raise exception 'clue_contains_digit' using errcode = 'P0001';
  end if;
  if cardinality(regexp_split_to_array(v_clue, E'\\s+')) > (v_cfg ->> 'clue_max_words')::int then
    raise exception 'clue_too_many_words' using errcode = 'P0001';
  end if;
  if char_length(v_clue) > (v_cfg ->> 'clue_max_chars')::int then
    raise exception 'clue_too_long' using errcode = 'P0001';
  end if;

  insert into public.wavelength_clues (match_id, round, clue)
  values (p_match_id, p_round, v_clue)
  on conflict (match_id, round) do update set clue = excluded.clue;
  insert into public.wavelength_clue_statuses (match_id, round)
  values (p_match_id, p_round)
  on conflict (match_id, round) do nothing;

  if not exists (
    select 1 from public.wavelength_rounds r
     where r.match_id = p_match_id
       and not exists (
         select 1 from public.wavelength_clue_statuses s
          where s.match_id = r.match_id and s.round = r.round
       )
  ) then
    update public.wavelength_matches
       set phase = 'guess',
           phase_deadline = now() + make_interval(secs => (v_cfg ->> 'guess_seconds')::int)
     where match_id = p_match_id;
    update public.wavelength_rounds
       set status = 'open'
     where match_id = p_match_id and round = v_board.current_round;
  end if;
  return wavelength_private.board_of(p_match_id);
end;
$$;

create function wavelength.lock_guess(
  p_match_id uuid,
  p_round    integer,
  p_position integer
)
returns wavelength.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user     uuid := auth.uid();
  v_board    public.wavelength_matches;
  v_target   smallint;
  v_distance integer;
  v_width    integer := (wavelength_private.config() ->> 'wedge_width')::integer;
  v_points   smallint;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_position is null or p_position not between 0 and (wavelength_private.config() ->> 'scale_max')::integer then
    raise exception 'position_out_of_range' using errcode = 'P0001';
  end if;

  -- The match-row lock serializes two clicks, as well as a concurrent tick.
  select wm.* into v_board
    from public.wavelength_matches wm
    join public.matches m on m.id = wm.match_id
   where wm.match_id = p_match_id
     and m.status = 'playing'::public.match_status
   for update of wm;
  if not found then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.wavelength_players
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  if v_board.phase <> 'guess' or v_board.current_round <> p_round then
    raise exception 'guess_not_open' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.wavelength_rounds
     where match_id = p_match_id
       and round = p_round
       and status = 'open'
       and guesser_id = v_user
  ) then
    raise exception 'not_guesser' using errcode = '42501';
  end if;

  select target into v_target
    from public.wavelength_targets
   where match_id = p_match_id and round = p_round;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0001';
  end if;

  v_distance := abs(p_position - v_target);
  -- Integer positions include each band edge in the higher-scoring band:
  -- 0..20 => 4, 21..60 => 3, and 61..100 => 2 when width is 40.
  v_points := case
    when v_distance <= v_width / 2 then 4
    when v_distance <= v_width * 3 / 2 then 3
    when v_distance <= v_width * 5 / 2 then 2
    else 0
  end;

  update public.wavelength_rounds
     set status = 'locked', points = v_points, revealed_target = v_target
   where match_id = p_match_id and round = p_round;

  if p_round < v_board.round_count then
    update public.wavelength_matches
       set current_round = p_round + 1,
           phase = 'guess',
           phase_deadline = now() + make_interval(secs => (wavelength_private.config() ->> 'guess_seconds')::int)
     where match_id = p_match_id;
    update public.wavelength_rounds
       set status = 'open'
     where match_id = p_match_id and round = p_round + 1;
  else
    -- #102 turns this all-rounds-revealed state into a result (and, for a
    -- tied versus match, creates sudden-death rounds).
    update public.wavelength_matches
       set phase = 'reveal', phase_deadline = null
     where match_id = p_match_id;
  end if;

  return wavelength_private.board_of(p_match_id);
end;
$$;

revoke all on function wavelength.lock_guess(uuid, integer, integer) from public, anon;
grant execute on function wavelength.lock_guess(uuid, integer, integer) to authenticated;
