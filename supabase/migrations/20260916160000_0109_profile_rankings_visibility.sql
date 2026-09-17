-- A player can opt out of being counted in *other* players' Ball Knower
-- cohort — the only thing "leaderboard visibility" means today, since there is
-- no page that lists other players by name. Their own total_points keeps
-- accruing either way; only the rank/percentile comparison drops them from
-- the denominator, and blanks their own percentile the same way "no resolved
-- picks yet" already does.
alter table public.profiles
  add column rankings_visible boolean not null default true;

drop function public.my_profile_knower_highlights();

create function public.my_profile_knower_highlights()
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
  -- The rank/percentile window only ever includes visible profiles, so a
  -- hidden player neither appears in anyone else's cohort nor shrinks the
  -- denominator on their behalf.
  visible_ranked as (
    select
      t.window_key,
      t.profile_id,
      ceil(
        (count(*) over (partition by t.window_key) - rank() over (partition by t.window_key order by t.total_points desc) + 1)::numeric
        * 100 / count(*) over (partition by t.window_key)
      )::integer as percentile
    from totals t
    join public.profiles p on p.id = t.profile_id and p.rankings_visible
  )
  select
    windows.window_key,
    coalesce(totals.total_points, 0)::integer,
    visible_ranked.percentile
  from windows
  left join totals
    on totals.window_key = windows.window_key and totals.profile_id = auth.uid()
  left join visible_ranked
    on visible_ranked.window_key = windows.window_key and visible_ranked.profile_id = auth.uid()
  order by case windows.window_key when 'lifetime' then 1 when 'year' then 2 when 'month' then 3 when 'week' then 4 end;
$$;

revoke all on function public.my_profile_knower_highlights() from public, anon;
grant execute on function public.my_profile_knower_highlights() to authenticated;
