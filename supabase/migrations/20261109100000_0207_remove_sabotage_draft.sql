-- Remove the Sabotage Draft game.
--
-- Everything the game owned goes: its pg_cron sweep, the twelve
-- `public.sabotage_draft_*` tables, the `sabotage_draft` and
-- `sabotage_draft_private` schemas (functions, the guess_result type, the
-- private boards/seasons tables), and every match, run and post-game action
-- that belonged to it. Nothing is archived; the data was agreed expendable.
--
-- Shared things stay: the `av_roster_players` / `av_player_headshots` pool
-- (QB Season Builder reads it) and the public `team-logos` Storage bucket
-- (created by 0068 for this game, but db:reset and the other games rely on it).

-- 1. Stop the sweep before touching its tables.
select cron.unschedule('sabotage-draft-sweep');

-- 2. Delete the game's matches. Remember their runs first: a run whose only
--    matches were Sabotage Draft ones would otherwise be left empty.
create temp table _sabotage_runs on commit drop as
  select distinct run_id from public.matches where game = 'sabotage_draft';

-- post_game_actions.next_match_id is ON DELETE RESTRICT; the match_id side
-- cascades, but a replay pointing at a Sabotage match has to go first.
delete from public.post_game_actions
 where next_match_id in (select id from public.matches where game = 'sabotage_draft');

-- Cascades to match_players, post_game_actions (match_id) and, through their
-- own match_id foreign keys, the game's tables.
delete from public.matches where game = 'sabotage_draft';

delete from public.runs r
 where r.id in (select run_id from _sabotage_runs)
   and not exists (select 1 from public.matches m where m.run_id = r.id);

-- 3. A lobby that had Sabotage Draft picked falls back to "no game picked".
update public.lobbies
   set selected_game = null, game_format = '{}'::jsonb
 where selected_game = 'sabotage_draft';

-- 4. The game's own objects.
drop table public.sabotage_draft_guesses,
           public.sabotage_draft_passes,
           public.sabotage_draft_pick_hits,
           public.sabotage_draft_pick_statuses,
           public.sabotage_draft_picks,
           public.sabotage_draft_round_spins,
           public.sabotage_draft_standings,
           public.sabotage_draft_tiebreak_games,
           public.sabotage_draft_x_factor_decisions,
           public.sabotage_draft_rounds,
           public.sabotage_draft_players,
           public.sabotage_draft_matches
  cascade;

drop schema sabotage_draft cascade;
drop schema sabotage_draft_private cascade;

-- 5. The game name leaves the allowed values.
alter table public.lobbies drop constraint lobbies_selected_game_check;
alter table public.lobbies add constraint lobbies_selected_game_check
  check (selected_game = any (array[
    'auction_team_builder', 'cards_against_humanity', 'higher_or_lower', 'wavelength_2v2'
  ]));

alter table public.matches drop constraint matches_game_check;
alter table public.matches add constraint matches_game_check
  check (game = any (array[
    'auction_team_builder', 'cards_against_humanity', 'higher_or_lower', 'wavelength_2v2',
    'qb_season_builder'
  ]));

-- 6. The two shared functions that had a Sabotage branch. Bodies are the live
--    ones (0200 and 0061/0165) minus that branch.
CREATE OR REPLACE FUNCTION private.begin_match_countdown(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_game text;
  v_mode public.run_mode;
  v_lead interval := private.match_start_lead();
begin
  select m.game, r.mode into v_game, v_mode
    from public.matches m join public.runs r on r.id = m.run_id
   where m.id = p_match_id;
  if v_mode is distinct from 'arcade'::public.run_mode then return; end if;

  update public.matches set play_starts_at = now() + v_lead where id = p_match_id;

  case v_game
    when 'auction_team_builder' then
      update public.auction_matches
         set turn_deadline = turn_deadline + v_lead, phase_deadline = phase_deadline + v_lead
       where match_id = p_match_id;
    when 'higher_or_lower' then
      update public.higher_or_lower_matches
         set phase_deadline = phase_deadline + v_lead
       where match_id = p_match_id;
    when 'wavelength_2v2' then
      update public.wavelength_matches
         set phase_deadline = phase_deadline + v_lead, phase_started_at = phase_started_at + v_lead
       where match_id = p_match_id;
    else null;
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION public.resume_match(p_match_id uuid)
 RETURNS matches
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_match public.matches; v_run public.runs; v_lobby public.lobbies; v_elapsed interval;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into v_match from public.matches where id = p_match_id for update; if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  select * into v_run from public.runs where id = v_match.run_id; if v_run.lobby_id is null then raise exception 'no_host' using errcode = '42501'; end if;
  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update; if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if not exists (select 1 from public.lobby_members where lobby_id = v_lobby.id and user_id = v_user and left_at is null) then raise exception 'not_a_member' using errcode = '42501'; end if;
  if v_match.status <> 'paused'::public.match_status then raise exception 'match_not_paused' using errcode = 'P0001'; end if;
  v_elapsed := now() - v_match.paused_at;
  case v_match.game when 'auction_team_builder' then update public.auction_matches set turn_deadline = turn_deadline + v_elapsed, phase_deadline = phase_deadline + v_elapsed where match_id = p_match_id;
    when 'higher_or_lower' then update public.higher_or_lower_matches set phase_deadline = phase_deadline + v_elapsed where match_id = p_match_id;
    when 'wavelength_2v2' then update public.wavelength_matches set phase_deadline = phase_deadline + v_elapsed, phase_started_at = phase_started_at + v_elapsed where match_id = p_match_id;
  end case;
  update public.matches set status = 'playing'::public.match_status, paused_at = null where id = p_match_id returning * into v_match; return v_match;
end;
$function$;
