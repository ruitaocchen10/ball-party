-- A completed match needs one durable, room-authoritative answer to “what's
-- next?”. Keeping it separate from matches preserves the completed result as
-- history while giving every final-screen client a small realtime event to
-- follow.
create type public.post_game_choice as enum ('replay', 'lobby');

create table public.post_game_actions (
  match_id        uuid primary key references public.matches(id) on delete cascade,
  choice          public.post_game_choice not null,
  next_match_id   uuid references public.matches(id) on delete restrict,
  chosen_at       timestamptz not null default now(),
  constraint post_game_actions_replay_target check (
    (choice = 'replay' and next_match_id is not null)
    or (choice = 'lobby' and next_match_id is null)
  )
);

alter table public.post_game_actions enable row level security;

-- The same current-room boundary as a match. A player who is no longer in the
-- room cannot receive an old room's navigation event over Realtime.
create policy post_game_actions_select_member on public.post_game_actions
  for select to authenticated using (
    exists (
      select 1
        from public.matches m
       where m.id = match_id
         and private.is_run_member(m.run_id)
    )
  );

alter publication supabase_realtime add table public.post_game_actions;

-- The host chooses the shared destination. Replay starts a new arcade run
-- from the completed run's immutable roster and auction format; it never
-- reopens or mutates the historical match.
create function public.choose_post_game(
  p_match_id uuid,
  p_choice public.post_game_choice
)
returns public.post_game_actions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_match public.matches;
  v_run public.runs;
  v_lobby public.lobbies;
  v_format public.auction_matches;
  v_next_run public.runs;
  v_next_match public.matches;
  v_action public.post_game_actions;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.status <> 'complete'::public.match_status then
    raise exception 'match_not_complete' using errcode = 'P0001';
  end if;

  select * into v_run from public.runs where id = v_match.run_id;
  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
  if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.lobby_members
     where lobby_id = v_lobby.id and user_id = v_user and left_at is null
  ) then raise exception 'not_a_member' using errcode = '42501'; end if;

  if exists (select 1 from public.post_game_actions where match_id = p_match_id) then
    raise exception 'post_game_choice_already_made' using errcode = 'P0001';
  end if;

  if p_choice = 'replay'::public.post_game_choice then
    if v_match.game <> 'auction_team_builder' then
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

    select * into v_format from public.auction_matches where match_id = p_match_id;
    if not found or v_format.scoring_mode is null or v_format.roster_preset is null then
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

    insert into public.runs (lobby_id, mode)
    values (v_lobby.id, 'arcade'::public.run_mode)
    returning * into v_next_run;

    insert into public.run_participants (run_id, user_id, seat)
    select v_next_run.id, user_id, seat
      from public.run_participants
     where run_id = v_run.id;

    insert into public.matches (run_id, game, seq, status)
    values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status)
    returning * into v_next_match;

    perform private.deal_auction_board(
      v_next_match.id, null, v_format.scoring_mode, v_format.roster_preset
    );
    update public.matches
       set status = 'playing'::public.match_status, started_at = now()
     where id = v_next_match.id;
    perform private.auction_advance(v_next_match.id);

    insert into public.post_game_actions (match_id, choice, next_match_id)
    values (p_match_id, p_choice, v_next_match.id)
    returning * into v_action;
  else
    insert into public.post_game_actions (match_id, choice)
    values (p_match_id, p_choice)
    returning * into v_action;
  end if;

  return v_action;
end;
$$;

revoke all on function public.choose_post_game(uuid, public.post_game_choice) from public, anon;
grant execute on function public.choose_post_game(uuid, public.post_game_choice) to authenticated;
