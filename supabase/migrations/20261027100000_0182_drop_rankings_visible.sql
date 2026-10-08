-- Drop profiles.rankings_visible (Friends, BPP-3).
--
-- Rankings are no longer opt-out: every account with enough scored picks is on
-- the Ball Knower board. Friends adds a single is_private flag later that hides
-- the profile body from non-friends, but a private player still ranks.
--
-- rankings_visible did one other job: delete_own_account set it to false so an
-- anonymized "Deleted player" left every cohort. That is now an explicit
-- deleted_at filter, so deleted accounts stay off the board without the column.
--
-- Production check before shipping (read-only): 0 of 8 real accounts had
-- rankings_visible = false, so no one who opted out becomes visible.
--
-- The 3-scored-pick floor (private.ball_knower_min_picks) is unchanged. So is
-- the leaderboard's return shape; only the standing status loses its 'hidden'
-- value, leaving 'ranked' and 'unranked'.

create or replace function private.ball_knower_cohort(p_window text)
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
    where profiles.deleted_at is null
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

-- status: 'ranked' (on the board) or 'unranked' (under the pick floor, which
-- includes no picks at all). Points and picks are the caller's own either way.
create or replace function public.my_ball_knower_standing(p_window text)
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

-- Percentile still ranks against every player with resolved picks in the
-- window (no pick floor, as before); only the visibility join is gone.
create or replace function public.my_profile_knower_highlights()
returns table (
  window_key text,
  total_points integer,
  percentile integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with windows as (
    select 'lifetime'::text as window_key, null::timestamptz as starts_at
    union all select 'year', now() - interval '365 days'
    union all select 'month', now() - interval '30 days'
    union all select 'week', now() - interval '7 days'
  ),
  totals as (
    select windows.window_key, responses.profile_id, sum(responses.points_earned)::integer as total_points
    from windows
    join public.prompt_posts posts on posts.status = 'resolved'
      and (windows.starts_at is null or posts.resolved_at >= windows.starts_at)
    join public.prompt_responses responses on responses.post_id = posts.id and responses.points_earned is not null
    group by windows.window_key, responses.profile_id
  ),
  ranked as (
    select
      t.window_key,
      t.profile_id,
      ceil(
        (count(*) over (partition by t.window_key) - rank() over (partition by t.window_key order by t.total_points desc) + 1)::numeric
        * 100 / count(*) over (partition by t.window_key)
      )::integer as percentile
    from totals t
    join public.profiles p on p.id = t.profile_id and p.deleted_at is null
  )
  select
    windows.window_key,
    coalesce(totals.total_points, 0)::integer,
    ranked.percentile
  from windows
  left join totals
    on totals.window_key = windows.window_key and totals.profile_id = auth.uid()
  left join ranked
    on ranked.window_key = windows.window_key and ranked.profile_id = auth.uid()
  order by case windows.window_key when 'lifetime' then 1 when 'year' then 2 when 'month' then 3 when 'week' then 4 end;
$$;

-- Same body as 0180 minus the rankings_visible write; deleted_at now does the
-- work of removing the account from rankings.
create or replace function public.delete_own_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  update public.profiles
     set display_name = 'Deleted player',
         avatar_url = null,
         deleted_at = coalesce(deleted_at, now())
   where id = v_user;

  update auth.users
     set banned_until = now() + interval '100 years'
   where id = v_user;
end;
$$;

alter table public.profiles drop column rankings_visible;
