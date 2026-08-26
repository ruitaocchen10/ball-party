-- Host pause/resume.
--
-- Every player-action RPC across all three games, and every game's cron
-- sweep, already gates on `mt.status = 'playing'` (see e.g. auction_private
-- .apply's `match_not_playing` check, and auction_private.sweep/
-- higher_or_lower_private.sweep/sabotage_draft_private.sweep's own `where
-- mt.status = 'playing'`). Flipping public.matches.status to a new 'paused'
-- value therefore blocks every action and stops every sweep from touching
-- the match, for free, with no changes to any of that code.
--
-- The one thing that genuinely needs new logic is the deadline itself: each
-- game's deadline column(s) are absolute timestamps, so a pause that lasts
-- any length of time leaves them in the past. Resuming has to shift them
-- forward by exactly how long the pause lasted, or the match would
-- self-expire the instant it resumed.

alter table public.matches
  add column paused_at timestamptz;

-- ---------------------------------------------------------------- pause --

create function public.pause_match(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
  v_run   public.runs;
  v_lobby public.lobbies;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  select * into v_run from public.runs where id = v_match.run_id;
  -- A solo run has no lobby and so no host to gate this on. Simplest correct
  -- answer for now is that solo matches cannot be paused at all.
  if v_run.lobby_id is null then raise exception 'no_host' using errcode = '42501'; end if;

  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
  if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.lobby_members
     where lobby_id = v_lobby.id and user_id = v_user and left_at is null
  ) then raise exception 'not_a_member' using errcode = '42501'; end if;

  if v_match.status <> 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  update public.matches
     set status = 'paused'::public.match_status, paused_at = now()
   where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

revoke all on function public.pause_match(uuid) from public, anon;
grant execute on function public.pause_match(uuid) to authenticated;

-- --------------------------------------------------------------- resume --

create function public.resume_match(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user    uuid := auth.uid();
  v_match   public.matches;
  v_run     public.runs;
  v_lobby   public.lobbies;
  v_elapsed interval;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  select * into v_run from public.runs where id = v_match.run_id;
  if v_run.lobby_id is null then raise exception 'no_host' using errcode = '42501'; end if;

  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
  if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.lobby_members
     where lobby_id = v_lobby.id and user_id = v_user and left_at is null
  ) then raise exception 'not_a_member' using errcode = '42501'; end if;

  if v_match.status <> 'paused'::public.match_status then
    raise exception 'match_not_paused' using errcode = 'P0001';
  end if;

  v_elapsed := now() - v_match.paused_at;

  -- Nulling out a column that was never set is a no-op (null + interval is
  -- null), so every branch is safe to run unconditionally even though each
  -- game only ever has a subset of its deadline columns populated at once.
  case v_match.game
    when 'auction_team_builder' then
      update public.auction_matches
         set turn_deadline = turn_deadline + v_elapsed,
             phase_deadline = phase_deadline + v_elapsed
       where match_id = p_match_id;
    when 'higher_or_lower' then
      update public.higher_or_lower_matches
         set phase_deadline = phase_deadline + v_elapsed
       where match_id = p_match_id;
    when 'sabotage_draft' then
      update public.sabotage_draft_matches
         set pick_deadline = pick_deadline + v_elapsed,
             guess_deadline = guess_deadline + v_elapsed
       where match_id = p_match_id;
    else
      null;
  end case;

  update public.matches
     set status = 'playing'::public.match_status, paused_at = null
   where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

revoke all on function public.resume_match(uuid) from public, anon;
grant execute on function public.resume_match(uuid) to authenticated;

-- ---------------------------------------------------------------- janitor --

-- A paused match's run status never changes on its own, so this is a
-- defensive extension, not something the normal pause/resume path relies on:
-- if a paused match's run does go inactive some other way, it should still
-- get swept eventually rather than sitting there forever with the janitor's
-- one existing run-inactivity check quietly skipping it because its status
-- is no longer 'playing'.
create or replace function auction_private.sweep()
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  r record;
  v_i int;
begin
  for r in
    select am.match_id
      from public.auction_matches am
      join public.matches mt on mt.id = am.match_id
     where mt.status = 'playing'::public.match_status
       and (
         (am.phase = 'bidding'
            and am.turn_deadline < now() - interval '1 minute')
         or (am.phase in ('lot_preview', 'sold')
            and am.phase_deadline < now() - interval '2 seconds')
       )
  loop
    for v_i in 1 .. 8 loop
      exit when not auction_private.expire(r.match_id);
    end loop;
  end loop;

  for r in
    select mt.id
      from public.matches mt
      join public.runs rn on rn.id = mt.run_id
     where mt.status in (
             'setup'::public.match_status,
             'playing'::public.match_status,
             'paused'::public.match_status
           )
       and rn.status <> 'active'::public.run_status
  loop
    perform private.abandon_match(r.id);
  end loop;

  for r in
    select mt.id
      from public.matches mt
      join public.runs rn on rn.id = mt.run_id
     where mt.status = 'setup'::public.match_status
       and rn.started_at < now() - interval '10 minutes'
  loop
    perform private.abandon_match(r.id);
  end loop;
end;
$function$
;
