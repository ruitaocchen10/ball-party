-- A status ladder needs a conventional percentile: higher is better. Replace
-- the earlier rank-oriented result with a 1–100 score where the top scorer is
-- 100, including a cohort containing only one active player.
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
  ranked as (
    select
      window_key,
      profile_id,
      total_points,
      ceil(
        (count(*) over (partition by window_key) - rank() over (partition by window_key order by total_points desc) + 1)::numeric
        * 100 / count(*) over (partition by window_key)
      )::integer as percentile
    from totals
  )
  select windows.window_key, coalesce(ranked.total_points, 0)::integer, ranked.percentile
  from windows
  left join ranked on ranked.window_key = windows.window_key and ranked.profile_id = auth.uid()
  order by case windows.window_key when 'lifetime' then 1 when 'year' then 2 when 'month' then 3 when 'week' then 4 end;
$$;

revoke all on function public.my_profile_knower_highlights() from public, anon;
grant execute on function public.my_profile_knower_highlights() to authenticated;
