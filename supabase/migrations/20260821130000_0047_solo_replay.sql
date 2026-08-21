-- Solo matches have no host because they have no lobby. Their sole participant
-- owns the same one-time post-game decision, and replay must preserve the
-- lobby-less run shape so the new Higher or Lower board is dealt as solo.
create or replace function public.choose_post_game(
  p_match_id uuid,
  p_choice public.post_game_choice,
  p_scoring_mode text default null,
  p_roster_preset text default null,
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns public.post_game_actions
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_user uuid := auth.uid();
  v_match public.matches;
  v_run public.runs;
  v_lobby public.lobbies;
  v_format public.auction_matches;
  v_hol public.higher_or_lower_matches;
  v_next_run public.runs;
  v_next_match public.matches;
  v_action public.post_game_actions;
  v_scoring_mode text;
  v_roster_preset text;
  v_season_from smallint;
  v_season_to smallint;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  select * into v_match from public.matches where id = p_match_id;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  select * into v_run from public.runs where id = v_match.run_id;
  if v_run.lobby_id is null then
    if not exists (
      select 1 from public.run_participants where run_id = v_run.id and user_id = v_user
    ) then
      raise exception 'not_match_participant' using errcode = '42501';
    end if;
  else
    select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
    if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  end if;

  if v_match.status <> 'complete'::public.match_status then
    raise exception 'match_not_complete' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.post_game_actions where match_id = p_match_id) then
    raise exception 'post_game_choice_already_made' using errcode = 'P0001';
  end if;

  if p_choice = 'replay'::public.post_game_choice then
    if v_match.game = 'auction_team_builder' then
      select * into v_format from public.auction_matches where match_id = p_match_id;
      if not found or v_format.scoring_mode is null or v_format.roster_preset is null then
        raise exception 'replay_not_supported' using errcode = 'P0001';
      end if;

      v_scoring_mode := coalesce(p_scoring_mode, v_format.scoring_mode);
      v_roster_preset := coalesce(p_roster_preset, v_format.roster_preset);
      v_season_from := coalesce(p_season_from, v_format.season_from);
      v_season_to := coalesce(p_season_to, v_format.season_to);

      if v_scoring_mode not in ('weekly', 'season_total') then
        raise exception 'invalid_scoring_mode' using errcode = 'P0001';
      end if;
      if v_roster_preset not in ('standard', 'full', 'deep') then
        raise exception 'invalid_roster_preset' using errcode = 'P0001';
      end if;
      perform auction_private.resolve_season_range(v_season_from, v_season_to);

      insert into public.runs (lobby_id, mode)
      values (
        case when v_run.lobby_id is null then null else v_lobby.id end,
        case when v_run.lobby_id is null then 'solo'::public.run_mode else 'arcade'::public.run_mode end
      )
      returning * into v_next_run;

      insert into public.run_participants (run_id, user_id, seat)
      select v_next_run.id, user_id, seat from public.run_participants where run_id = v_run.id;

      insert into public.matches (run_id, game, seq, status)
      values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status)
      returning * into v_next_match;

      perform auction_private.deal_board(
        v_next_match.id, null, v_scoring_mode, v_roster_preset, v_season_from, v_season_to
      );
      update public.matches set status = 'playing'::public.match_status, started_at = now()
       where id = v_next_match.id;
      perform auction_private.advance(v_next_match.id);

    elsif v_match.game = 'higher_or_lower' then
      select * into v_hol from public.higher_or_lower_matches where match_id = p_match_id;
      if not found then raise exception 'replay_not_supported' using errcode = 'P0001'; end if;

      v_season_from := coalesce(p_season_from, v_hol.season_from);
      v_season_to := coalesce(p_season_to, v_hol.season_to);

      insert into public.runs (lobby_id, mode)
      values (
        case when v_run.lobby_id is null then null else v_lobby.id end,
        case when v_run.lobby_id is null then 'solo'::public.run_mode else 'arcade'::public.run_mode end
      )
      returning * into v_next_run;

      insert into public.run_participants (run_id, user_id, seat)
      select v_next_run.id, user_id, seat from public.run_participants where run_id = v_run.id;

      insert into public.matches (run_id, game, seq, status)
      values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status)
      returning * into v_next_match;

      perform higher_or_lower_private.deal_board(
        v_next_match.id, null, v_hol.scoring_mode, v_season_from, v_season_to
      );
      update public.matches set status = 'playing'::public.match_status, started_at = now()
       where id = v_next_match.id;
      update public.higher_or_lower_matches
         set phase = 'board_intro', phase_deadline = now() + interval '5 seconds'
       where match_id = v_next_match.id;

    else
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

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
