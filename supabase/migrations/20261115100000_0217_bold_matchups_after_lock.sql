-- Bold Predictions can now be taken across the week's games (BPP-15): a post
-- opens on the Saturday and locks at the week's first Sunday kickoff, so by
-- the lock the Thursday game has already been played. A matchup tag therefore
-- has to be one of the week's games that has not kicked off at lock_at, i.e.
-- the games the post can still be about. The week itself is decided as before
-- (0171): the week of the first game at or after lock_at.
create or replace function prompts_private.validate_bold_target(p_post public.prompt_posts, p_type text, p_id text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_type = 'matchup' then
    if not exists (
      select 1
        from public.nfl_games g
        join prompts_private.bold_prediction_week(p_post.lock_at) w
          on w.season = g.season and w.week = g.week
       where g.id = p_id
         and g.kickoff >= p_post.lock_at
    ) then
      raise exception 'invalid_target' using errcode = '22023', detail = 'matchup';
    end if;
  elsif p_type = 'team' then
    if not prompts_private.is_valid_team_code(p_id) then
      raise exception 'invalid_target' using errcode = '22023', detail = 'team';
    end if;
  elsif p_type = 'player' then
    if not prompts_private.is_valid_player_id(p_id) then
      raise exception 'invalid_target' using errcode = '22023', detail = 'player';
    end if;
  else
    raise exception 'invalid_target' using errcode = '22023', detail = 'target_type';
  end if;
end;
$$;

revoke all on function prompts_private.validate_bold_target(public.prompt_posts, text, text) from public, anon, authenticated;
