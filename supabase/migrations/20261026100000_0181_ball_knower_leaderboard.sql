-- Ball Knower leaderboard (BPP-1).
--
-- my_profile_knower_highlights (0107-0109) already totals each player's
-- resolved prompt points over the week / month / year / lifetime windows and
-- already honours profiles.rankings_visible. What was missing is anything that
-- lists *other* players. This adds two narrow reads and the cohort they share:
--
--   * ball_knower_leaderboard(window, limit): the ranked list.
--   * my_ball_knower_standing(window): the caller's own row and why they are or
--     are not on the list, so a client can pin "you" without scanning the list.
--
-- The cohort is visible players (rankings_visible) with at least
-- private.ball_knower_min_picks() scored picks in the window, so one lucky pick
-- cannot top a quiet week. Ties share a rank (rank(), so 1, 1, 3) and are
-- listed by display name. my_profile_knower_highlights is deliberately left
-- alone: its percentile still ranks against every visible player, floor or not.
--
-- Signed-in only (guests included, they hold the authenticated role). Both
-- functions are SECURITY DEFINER because prompt_responses is self-only under
-- RLS; they return display name, avatar and totals, never individual answers.

create function private.ball_knower_min_picks()
returns integer
language sql
immutable
set search_path = ''
as $$ select 3 $$;

-- Every player's total and scored-pick count in the window, with no
-- visibility or floor applied. Windows match my_profile_knower_highlights:
-- rolling 7/30/365 days on the post's resolved_at, lifetime unbounded.
create function private.ball_knower_totals(p_window text)
returns table (profile_id uuid, total_points integer, scored_picks integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    responses.profile_id,
    sum(responses.points_earned)::integer,
    count(*)::integer
  from public.prompt_posts posts
  join public.prompt_responses responses
    on responses.post_id = posts.id
   and responses.points_earned is not null
  where posts.status = 'resolved'
    and (
      p_window = 'lifetime'
      or posts.resolved_at >= now() - case p_window
        when 'week'  then interval '7 days'
        when 'month' then interval '30 days'
        when 'year'  then interval '365 days'
      end
    )
  group by responses.profile_id;
$$;

create function private.ball_knower_cohort(p_window text)
returns table (
  profile_id uuid,
  display_name text,
  avatar_url text,
  total_points integer,
  scored_picks integer,
  rank integer,
  ranked_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with eligible as (
    select totals.profile_id, profiles.display_name, profiles.avatar_url,
           totals.total_points, totals.scored_picks
    from private.ball_knower_totals(p_window) totals
    join public.profiles profiles on profiles.id = totals.profile_id
    where profiles.rankings_visible
      and totals.scored_picks >= private.ball_knower_min_picks()
  )
  select
    eligible.profile_id,
    eligible.display_name,
    eligible.avatar_url,
    eligible.total_points,
    eligible.scored_picks,
    (rank() over (order by eligible.total_points desc))::integer,
    (count(*) over ())::integer
  from eligible;
$$;

revoke all on function private.ball_knower_min_picks() from public, anon, authenticated;
revoke all on function private.ball_knower_totals(text) from public, anon, authenticated;
revoke all on function private.ball_knower_cohort(text) from public, anon, authenticated;

-- ------------------------------------------------------------- public reads --

create function public.ball_knower_leaderboard(p_window text, p_limit integer default 50)
returns table (
  rank integer,
  profile_id uuid,
  display_name text,
  avatar_url text,
  total_points integer,
  scored_picks integer,
  is_me boolean,
  ranked_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_window is null or p_window not in ('week', 'month', 'year', 'lifetime') then
    raise exception 'invalid_window' using errcode = '22023';
  end if;

  return query
    select cohort.rank, cohort.profile_id, cohort.display_name, cohort.avatar_url,
           cohort.total_points, cohort.scored_picks,
           cohort.profile_id = auth.uid(), cohort.ranked_count
    from private.ball_knower_cohort(p_window) cohort
    order by cohort.rank, cohort.display_name, cohort.profile_id
    limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

-- status: 'ranked' (on the board), 'hidden' (rankings_visible is off), or
-- 'unranked' (visible but under the pick floor, which includes no picks at
-- all). Points and picks are the caller's own either way.
create function public.my_ball_knower_standing(p_window text)
returns table (
  status text,
  rank integer,
  total_points integer,
  scored_picks integer,
  ranked_count integer,
  min_picks integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_window is null or p_window not in ('week', 'month', 'year', 'lifetime') then
    raise exception 'invalid_window' using errcode = '22023';
  end if;

  return query
    with mine as (
      select totals.total_points, totals.scored_picks
      from private.ball_knower_totals(p_window) totals
      where totals.profile_id = v_me
    ),
    cohort as (
      select * from private.ball_knower_cohort(p_window)
    )
    select
      case
        when me_ranked.profile_id is not null then 'ranked'
        when not (select rankings_visible from public.profiles where id = v_me) then 'hidden'
        else 'unranked'
      end,
      me_ranked.rank,
      coalesce((select mine.total_points from mine), 0),
      coalesce((select mine.scored_picks from mine), 0),
      (select count(*)::integer from cohort),
      private.ball_knower_min_picks()
    from (select 1) one
    left join cohort me_ranked on me_ranked.profile_id = v_me;
end;
$$;

revoke all on function public.ball_knower_leaderboard(text, integer) from public, anon;
revoke all on function public.my_ball_knower_standing(text) from public, anon;
grant execute on function public.ball_knower_leaderboard(text, integer) to authenticated;
grant execute on function public.my_ball_knower_standing(text) to authenticated;
