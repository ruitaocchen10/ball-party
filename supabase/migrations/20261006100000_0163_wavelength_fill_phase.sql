-- 2v2 Wavelength: parallel clue writing during the fill phase (issue #99).
--
-- A clue has its own row rather than a column on wavelength_rounds because RLS
-- filters rows, not columns.  Until #100 opens a round, only its psychic can
-- read this row; everyone else sees only wavelength_clue_statuses.

create table public.wavelength_clues (
  match_id uuid not null,
  round    smallint not null,
  clue     text not null check (clue <> ''),

  primary key (match_id, round),
  foreign key (match_id, round)
    references public.wavelength_rounds (match_id, round) on delete cascade
);

alter table public.wavelength_clues enable row level security;
revoke all on public.wavelength_clues from anon, authenticated;

create policy wavelength_clues_select_psychic on public.wavelength_clues
  for select to authenticated
  using (
    exists (
      select 1
        from public.wavelength_rounds r
       where r.match_id = wavelength_clues.match_id
         and r.round = wavelength_clues.round
         and r.psychic_id = auth.uid()
    )
  );

grant select on public.wavelength_clues to authenticated;

create function wavelength.submit_clue(
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

  -- This is the serialization point for the final simultaneous clue: it makes
  -- the all-written check and the fill-to-guess transition one atomic action.
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

  -- Replacing is intentional: a psychic can correct a typo until fill closes.
  -- The status insert is idempotent so a replacement never creates a second
  -- public signal.
  insert into public.wavelength_clues (match_id, round, clue)
  values (p_match_id, p_round, v_clue)
  on conflict (match_id, round) do update set clue = excluded.clue;

  insert into public.wavelength_clue_statuses (match_id, round)
  values (p_match_id, p_round)
  on conflict (match_id, round) do nothing;

  if not exists (
    select 1
      from public.wavelength_rounds r
     where r.match_id = p_match_id
       and not exists (
         select 1 from public.wavelength_clue_statuses s
          where s.match_id = r.match_id and s.round = r.round
       )
  ) then
    update public.wavelength_matches
       set phase = 'guess', phase_deadline = null
     where match_id = p_match_id;
    update public.wavelength_rounds
       set status = 'open'
     where match_id = p_match_id and round = v_board.current_round;
  end if;

  return wavelength_private.board_of(p_match_id);
end;
$$;

revoke all on function wavelength.submit_clue(uuid, integer, text) from public, anon;
grant execute on function wavelength.submit_clue(uuid, integer, text) to authenticated;
