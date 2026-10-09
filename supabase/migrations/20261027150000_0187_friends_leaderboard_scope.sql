-- Friends scope for the Ball Knower leaderboard (Friends, BPP-3).
--
-- ball_knower_leaderboard and my_ball_knower_standing gain a p_scope argument:
--   'all'     (default) everyone, exactly as before;
--   'friends' the caller plus their accepted friends.
-- Ranking, ties, the pick floor and the windows are the same code; the scope
-- only narrows who is in the cohort before ranks are assigned, so a friends
-- board ranks the caller against friends (rank 1 = best among them) and
-- ranked_count is the size of that smaller group. A private profile still
-- ranks, as everywhere. Friends scope needs a real account (guests have no
-- friends) and raises guests_cannot_have_friends for them.
--
-- The functions are dropped and recreated because the argument list changes;
-- callers that pass only p_window (and p_limit) keep working through the
-- default.

drop function public.ball_knower_leaderboard(text, integer);
drop function public.my_ball_knower_standing(text);
drop function private.ball_knower_cohort(text);

create function private.ball_knower_cohort(p_window text, p_scope text, p_viewer uuid)
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
  with friend_ids as (
    select case when f.requester_id = p_viewer then f.addressee_id else f.requester_id end as id
      from public.friendships f
     where f.status = 'accepted' and p_viewer in (f.requester_id, f.addressee_id)
  ),
  eligible as (
    select totals.profile_id, profiles.display_name, profiles.avatar_url,
           totals.total_points, totals.scored_picks
    from private.ball_knower_totals(p_window) totals
    join public.profiles profiles on profiles.id = totals.profile_id
    where profiles.deleted_at is null
      and totals.scored_picks >= private.ball_knower_min_picks()
      and (
        p_scope = 'all'
        or totals.profile_id = p_viewer
        or totals.profile_id in (select id from friend_ids)
      )
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
revoke all on function private.ball_knower_cohort(text, text, uuid) from public, anon, authenticated;

create function public.ball_knower_leaderboard(
  p_window text,
  p_limit integer default 50,
  p_scope text default 'all'
)
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
  if p_scope is null or p_scope not in ('all', 'friends') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;
  if p_scope = 'friends' then
    perform private.friend_caller();
  end if;

  return query
    select cohort.rank, cohort.profile_id, cohort.display_name, cohort.avatar_url,
           cohort.total_points, cohort.scored_picks,
           cohort.profile_id = auth.uid(), cohort.ranked_count
    from private.ball_knower_cohort(p_window, p_scope, auth.uid()) cohort
    order by cohort.rank, cohort.display_name, cohort.profile_id
    limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

-- status: 'ranked' (on the board) or 'unranked' (under the pick floor, which
-- includes no picks at all). Points and picks are the caller's own either way;
-- ranked_count is the size of the chosen scope's board.
create function public.my_ball_knower_standing(p_window text, p_scope text default 'all')
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
  if p_scope is null or p_scope not in ('all', 'friends') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;
  if p_scope = 'friends' then
    perform private.friend_caller();
  end if;

  return query
    with mine as (
      select totals.total_points, totals.scored_picks
      from private.ball_knower_totals(p_window) totals
      where totals.profile_id = v_me
    ),
    cohort as (
      select * from private.ball_knower_cohort(p_window, p_scope, v_me)
    )
    select
      case when me_ranked.profile_id is not null then 'ranked' else 'unranked' end,
      me_ranked.rank,
      coalesce((select mine.total_points from mine), 0),
      coalesce((select mine.scored_picks from mine), 0),
      (select count(*)::integer from cohort),
      private.ball_knower_min_picks()
    from (select 1) one
    left join cohort me_ranked on me_ranked.profile_id = v_me;
end;
$$;

revoke all on function public.ball_knower_leaderboard(text, integer, text) from public, anon;
revoke all on function public.my_ball_knower_standing(text, text) from public, anon;
grant execute on function public.ball_knower_leaderboard(text, integer, text) to authenticated;
grant execute on function public.my_ball_knower_standing(text, text) to authenticated;
