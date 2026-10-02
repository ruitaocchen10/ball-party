-- Wavelength: remember where the needle sat, and where each guess landed.
--
-- 1. Auto-lock (#101) is specified to lock "where the needle currently sits",
--    but the server never learned the needle position and always locked the
--    midpoint.  The active guesser now reports it (throttled by the client);
--    tick uses the last report.  It lives in a private table because it is
--    ephemeral input, not state any client reads or subscribes to.
-- 2. The reveal (#104) must draw the locked needle next to the target, so the
--    round row now records the position it was locked at.  It is public once
--    the round is locked, like points and revealed_target.

alter table public.wavelength_rounds add column guess_position smallint
  check (guess_position between 0 and 1000);

create table wavelength_private.needles (
  match_id uuid     not null,
  round    smallint not null,
  position smallint not null check (position between 0 and 1000),

  primary key (match_id, round),
  foreign key (match_id, round)
    references public.wavelength_rounds (match_id, round) on delete cascade
);

alter table wavelength_private.needles enable row level security;
revoke all on wavelength_private.needles from public, anon, authenticated;

create function wavelength.report_needle(p_match_id uuid, p_round integer, p_position integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_scale integer := (wavelength_private.config() ->> 'scale_max')::integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_position is null or p_position not between 0 and v_scale then
    raise exception 'position_out_of_range' using errcode = 'P0001';
  end if;

  -- Only the open round's guesser may report, while its guess is still open.
  if not exists (
    select 1
      from public.wavelength_matches wm
      join public.wavelength_rounds r
        on r.match_id = wm.match_id and r.round = wm.current_round
     where wm.match_id = p_match_id
       and wm.phase = 'guess'
       and wm.current_round = p_round
       and r.status = 'open'
       and r.guesser_id = v_user
  ) then
    raise exception 'not_guesser' using errcode = '42501';
  end if;

  insert into wavelength_private.needles (match_id, round, position)
  values (p_match_id, p_round, p_position)
  on conflict (match_id, round) do update set position = excluded.position;
end;
$$;

revoke all on function wavelength.report_needle(uuid, integer, integer) from public, anon;
grant execute on function wavelength.report_needle(uuid, integer, integer) to authenticated;

-- settle_guess as in 0166, now recording where the guess landed.
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
  v_next   smallint;
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

  select min(round) into v_next from public.wavelength_rounds
   where match_id = p_match_id and status = 'pending' and round > p_round;
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
end;
$$;

-- tick as in 0166, except an expired guess locks at the guesser's last
-- reported needle position (the midpoint if they never reported one).
create or replace function wavelength.tick(p_match_id uuid)
returns wavelength.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user    uuid := auth.uid();
  v_match   public.matches;
  v_board   public.wavelength_matches;
  v_round   smallint;
  v_default integer := (wavelength_private.config() ->> 'scale_max')::integer / 2;
  v_needle  integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found or v_match.status <> 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;
  update public.wavelength_players set last_seen_at = now(), absent = false
   where match_id = p_match_id and user_id = v_user;
  if not found then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  select * into v_board from public.wavelength_matches where match_id = p_match_id for update;
  if v_board.phase_deadline is null or v_board.phase_deadline > now() then
    return wavelength_private.board_of(p_match_id);
  end if;

  if v_board.phase = 'fill' then
    update public.wavelength_rounds r
       set status = 'skipped', points = 0, revealed_target = t.target
      from public.wavelength_targets t
     where r.match_id = p_match_id and r.match_id = t.match_id and r.round = t.round
       and r.status = 'pending'
       and not exists (
         select 1 from public.wavelength_clue_statuses s
          where s.match_id = r.match_id and s.round = r.round
       );
    perform wavelength_private.latch_absent(p_match_id, v_board.phase_started_at);
    select min(round) into v_round from public.wavelength_rounds
     where match_id = p_match_id and status = 'pending';
    if v_round is null then
      perform wavelength_private.finish_if_ready(p_match_id);
    else
      update public.wavelength_matches
         set current_round = v_round, phase = 'guess',
             phase_deadline = now() + make_interval(secs => (wavelength_private.config() ->> 'guess_seconds')::int),
             phase_started_at = now()
       where match_id = p_match_id;
      update public.wavelength_rounds set status = 'open'
       where match_id = p_match_id and round = v_round;
    end if;
  elsif v_board.phase = 'guess' then
    select position into v_needle from wavelength_private.needles
     where match_id = p_match_id and round = v_board.current_round;
    perform wavelength_private.settle_guess(
      p_match_id, v_board.current_round, coalesce(v_needle, v_default));
  end if;
  return wavelength_private.board_of(p_match_id);
end;
$$;

revoke all on function wavelength.tick(uuid) from public, anon;
grant execute on function wavelength.tick(uuid) to authenticated;
