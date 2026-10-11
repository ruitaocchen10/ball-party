-- Wavelength: a locked guess holds on its card until the host moves on.
--
-- Until now settle_guess opened the next card the moment a guess locked, so
-- players never saw the target, the needle and the points before the table
-- moved on.  It now parks the match in `reveal` (no deadline, current_round
-- unchanged) and the host calls wavelength.next_card to open the next card,
-- or to finish the match after the last one.  Click, auto-lock and the final
-- card all settle through settle_guess, so they behave the same.

create or replace function wavelength_private.settle_guess(p_match_id uuid, p_round smallint, p_position integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board  public.wavelength_matches;
  v_target smallint;
  v_width  integer := (wavelength_private.config() ->> 'wedge_width')::integer;
  v_points smallint;
begin
  select * into v_board from public.wavelength_matches where match_id = p_match_id;
  select target into v_target from public.wavelength_targets
   where match_id = p_match_id and round = p_round;

  v_points := case
    when abs(p_position - v_target) <= v_width / 2 then 4
    when abs(p_position - v_target) <= v_width * 3 / 2 then 3
    when abs(p_position - v_target) <= v_width * 5 / 2 then 2
    else 0 end;

  update public.wavelength_rounds
     set status = 'locked', points = v_points, revealed_target = v_target,
         guess_position = p_position
   where match_id = p_match_id and round = p_round;
  perform wavelength_private.latch_absent(p_match_id, v_board.phase_started_at);

  update public.wavelength_matches
     set phase = 'reveal', phase_deadline = null, phase_started_at = now()
   where match_id = p_match_id;
end;
$$;

create function wavelength.next_card(p_match_id uuid)
returns wavelength.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
  v_run   public.runs;
  v_lobby public.lobbies;
  v_board public.wavelength_matches;
  v_next  smallint;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found or v_match.status <> 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;
  select * into v_run from public.runs where id = v_match.run_id;
  if v_run.lobby_id is null then
    raise exception 'no_host' using errcode = '42501';
  end if;
  select * into v_lobby from public.lobbies where id = v_run.lobby_id;
  if v_lobby.host_id <> v_user then
    raise exception 'not_host' using errcode = '42501';
  end if;
  if not exists (select 1 from public.wavelength_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  select * into v_board from public.wavelength_matches where match_id = p_match_id for update;
  if v_board.phase <> 'reveal' then
    raise exception 'reveal_not_open' using errcode = 'P0001';
  end if;

  select min(round) into v_next from public.wavelength_rounds
   where match_id = p_match_id and status = 'pending' and round > v_board.current_round;
  if v_next is not null then
    update public.wavelength_matches
       set current_round = v_next, phase = 'guess',
           phase_deadline = now() + make_interval(secs => (wavelength_private.config() ->> 'guess_seconds')::int),
           phase_started_at = now()
     where match_id = p_match_id;
    update public.wavelength_rounds set status = 'open'
     where match_id = p_match_id and round = v_next;
  else
    perform wavelength_private.finish_if_ready(p_match_id);
  end if;
  return wavelength_private.board_of(p_match_id);
end;
$$;

revoke all on function wavelength.next_card(uuid) from public, anon;
grant execute on function wavelength.next_card(uuid) to authenticated;
