create or replace function higher_or_lower.start(
  p_match_id uuid, p_scoring_mode text default 'season_total',
  p_season_from smallint default null, p_season_to smallint default null
) returns higher_or_lower.board
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode not in ('weekly', 'season_total') then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  perform higher_or_lower_private.resolve_season_range(p_season_from, p_season_to);
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'higher_or_lower' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform higher_or_lower_private.deal_board(p_match_id, null, p_scoring_mode, p_season_from, p_season_to);
  update public.matches set status = 'playing', started_at = now() where id = p_match_id;
  update public.higher_or_lower_matches set phase = 'board_intro', phase_deadline = now() + interval '5 seconds' where match_id = p_match_id;
  return higher_or_lower_private.board_of(p_match_id);
end;
$$;
