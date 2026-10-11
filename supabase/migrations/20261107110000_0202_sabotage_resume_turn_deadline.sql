-- Resuming a paused Sabotage Draft failed: resume_match shifted two columns,
-- pick_deadline and guess_deadline, that sabotage_draft_matches no longer has
-- (its one clock is turn_deadline), so the host's Resume raised 42703 and the
-- match stayed paused. Shift turn_deadline instead.

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
    when 'sabotage_draft' then update public.sabotage_draft_matches set turn_deadline = turn_deadline + v_elapsed where match_id = p_match_id;
    when 'wavelength_2v2' then update public.wavelength_matches set phase_deadline = phase_deadline + v_elapsed, phase_started_at = phase_started_at + v_elapsed where match_id = p_match_id;
  end case;
  update public.matches set status = 'playing'::public.match_status, paused_at = null where id = p_match_id returning * into v_match; return v_match;
end;
$function$;
