-- The ladder's rhythm belongs to the match, not to a browser. A participant
-- can ask this machine to tick, but its deadline is checked under the board
-- lock in server time, so an early, duplicate, or racing request is harmless.

alter table public.higher_or_lower_matches
  add column phase text not null default 'board_intro'
    check (phase in ('board_intro', 'call', 'reveal', 'complete')),
  add column phase_deadline timestamptz;

-- Boards dealt before this migration had no clock. Start them at the same
-- introduction a new board receives rather than leaving a silent live match.
update public.higher_or_lower_matches hm
   set phase = 'board_intro', phase_deadline = now() + interval '5 seconds'
  from public.matches mt
 where mt.id = hm.match_id
   and mt.status = 'playing'::public.match_status;

alter type higher_or_lower.board add attribute phase text;
alter type higher_or_lower.board add attribute phase_deadline timestamptz;
alter type higher_or_lower.board add attribute server_now timestamptz;

create or replace function higher_or_lower_private.board_of(p_match_id uuid)
returns higher_or_lower.board
language sql
stable
security definer
set search_path = ''
as $$
  select (m.match_id, m.question_count, m.spare_count, m.current_question,
          m.scoring_mode, m.season_from, m.season_to, m.phase,
          m.phase_deadline, now())::higher_or_lower.board
    from public.higher_or_lower_matches m
   where m.match_id = p_match_id;
$$;

-- Advance exactly one expired phase. The match lock is the concurrency rule:
-- one caller observes the old deadline, moves it into the future, and every
-- waiter observes that new deadline before it can make a second transition.
create function higher_or_lower_private.expire(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.higher_or_lower_matches;
  v_scores jsonb;
begin
  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of hm;

  if not found or v_board.phase_deadline is null or v_board.phase_deadline > now() then
    return false;
  end if;

  if v_board.phase = 'board_intro' then
    update public.higher_or_lower_matches
       set phase = 'call', phase_deadline = now() + interval '12 seconds'
     where match_id = p_match_id;
  elsif v_board.phase = 'call' then
    update public.higher_or_lower_cards c
       set points = a.points, revealed_at = now()
      from higher_or_lower_private.answers a
     where c.match_id = p_match_id
       and c.ordinal = v_board.current_question
       and a.match_id = c.match_id
       and a.ordinal = c.ordinal;

    update public.higher_or_lower_matches
       set phase = 'reveal', phase_deadline = now() + interval '4 seconds'
     where match_id = p_match_id;
  elsif v_board.phase = 'reveal' then
    if v_board.current_question >= v_board.question_count then
      update public.higher_or_lower_matches
         set phase = 'complete', phase_deadline = null
       where match_id = p_match_id;

      select jsonb_object_agg(user_id::text, 0) into v_scores
        from public.higher_or_lower_players
       where match_id = p_match_id;
      perform private.finish_match(p_match_id, coalesce(v_scores, '{}'::jsonb));
    else
      update public.higher_or_lower_matches
         set current_question = current_question + 1,
             phase = 'call', phase_deadline = now() + interval '12 seconds'
       where match_id = p_match_id;
    end if;
  else
    return false;
  end if;

  return true;
end;
$$;

-- The exposed read is the reconnect contract. It is deliberately a projection
-- so future private board columns never reach a client merely by being added.
create function higher_or_lower.state(p_match_id uuid)
returns higher_or_lower.board
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  return higher_or_lower_private.board_of(p_match_id);
end;
$$;

-- Any participant may ask for expiry. It does not matter who gets there
-- first: expire re-checks its own deadline while holding the board lock.
create function higher_or_lower.tick(p_match_id uuid)
returns higher_or_lower.board
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.higher_or_lower_players
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  perform higher_or_lower_private.expire(p_match_id);
  return higher_or_lower_private.board_of(p_match_id);
end;
$$;

create or replace function higher_or_lower.start(
  p_match_id uuid,
  p_scoring_mode text default 'season_total',
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns higher_or_lower.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode = 'weekly' then
    raise exception 'scoring_mode_not_supported' using errcode = 'P0001';
  elsif p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  perform higher_or_lower_private.resolve_season_range(p_season_from, p_season_to);

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'higher_or_lower' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (
    select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user
  ) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;

  perform higher_or_lower_private.deal_board(
    p_match_id, null, p_scoring_mode, p_season_from, p_season_to
  );
  update public.matches set status = 'playing'::public.match_status, started_at = now()
   where id = p_match_id;
  update public.higher_or_lower_matches
     set phase = 'board_intro', phase_deadline = now() + interval '5 seconds'
   where match_id = p_match_id;

  return higher_or_lower_private.board_of(p_match_id);
end;
$$;

-- The sweep only rescues a stalled match. A call has a human decision in it,
-- so it gets a generous grace; intro and reveal have nobody to protect.
create function higher_or_lower_private.sweep()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare r record;
begin
  for r in
    select hm.match_id
      from public.higher_or_lower_matches hm
      join public.matches mt on mt.id = hm.match_id
     where mt.status = 'playing'::public.match_status
       and (
         (hm.phase = 'call' and hm.phase_deadline < now() - interval '1 minute')
         or (hm.phase in ('board_intro', 'reveal') and hm.phase_deadline < now() - interval '2 seconds')
       )
  loop
    perform higher_or_lower_private.expire(r.match_id);
  end loop;
end;
$$;

-- A client clock is the fast path. The one-minute sweep catches games nobody
-- has open without making the live call phase impatient.
select cron.schedule(
  'higher-or-lower-sweep',
  '* * * * *',
  $$ select higher_or_lower_private.sweep() $$
);

revoke all on function higher_or_lower_private.expire(uuid) from public, anon, authenticated;
revoke all on function higher_or_lower_private.sweep() from public, anon, authenticated;
revoke all on function higher_or_lower.state(uuid) from public, anon;
revoke all on function higher_or_lower.tick(uuid) from public, anon;
revoke all on function higher_or_lower.start(uuid, text, smallint, smallint) from public, anon;
grant execute on function higher_or_lower.state(uuid) to authenticated;
grant execute on function higher_or_lower.tick(uuid) to authenticated;
grant execute on function higher_or_lower.start(uuid, text, smallint, smallint) to authenticated;
