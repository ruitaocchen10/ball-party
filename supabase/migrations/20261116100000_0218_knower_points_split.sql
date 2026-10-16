-- The profile's Ball Knower card splits a window's points into pick points and
-- like points (net balls). total_points is unchanged (still
-- private.ball_knower_totals, so it matches the board); the split is returned
-- beside it so the clients draw it and never recompute it.

create function private.ball_knower_split(p_window text)
returns table (profile_id uuid, pick_points integer, like_points integer)
language sql
stable
security definer
set search_path = ''
as $$
  with picks as (
    select responses.profile_id, sum(responses.points_earned)::integer as points
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
     group by responses.profile_id
  ),
  balls as (
    select c.author_id as profile_id, sum(r.value)::integer as net
      from public.take_reactions r
      join public.prompt_comments c on c.id = r.comment_id
     where p_window = 'lifetime'
        or r.updated_at >= now() - case p_window
          when 'week'  then interval '7 days'
          when 'month' then interval '30 days'
          when 'year'  then interval '365 days'
        end
     group by c.author_id
  )
  select coalesce(picks.profile_id, balls.profile_id),
         coalesce(picks.points, 0)::integer,
         coalesce(balls.net, 0)::integer
    from picks
    full join balls on balls.profile_id = picks.profile_id;
$$;
revoke all on function private.ball_knower_split(text) from public, anon, authenticated;

drop function public.my_profile_knower_highlights();
drop function public.get_profile_knower_highlights(uuid);
drop function private.knower_highlights(uuid);

create function private.knower_highlights(p_profile uuid)
returns table (
  window_key text,
  total_points integer,
  percentile integer,
  pick_points integer,
  like_points integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with windows as (
    select unnest(array['lifetime', 'year', 'month', 'week']) as window_key
  ),
  totals as (
    select windows.window_key, t.profile_id, t.total_points
      from windows
     cross join lateral private.ball_knower_totals(windows.window_key) t
  ),
  splits as (
    select windows.window_key, s.profile_id, s.pick_points, s.like_points
      from windows
     cross join lateral private.ball_knower_split(windows.window_key) s
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
    ranked.percentile,
    coalesce(splits.pick_points, 0)::integer,
    coalesce(splits.like_points, 0)::integer
  from windows
  left join totals
    on totals.window_key = windows.window_key and totals.profile_id = p_profile
  left join splits
    on splits.window_key = windows.window_key and splits.profile_id = p_profile
  left join ranked
    on ranked.window_key = windows.window_key and ranked.profile_id = p_profile
  order by case windows.window_key when 'lifetime' then 1 when 'year' then 2 when 'month' then 3 when 'week' then 4 end;
$$;
revoke all on function private.knower_highlights(uuid) from public, anon, authenticated;

create function public.my_profile_knower_highlights()
returns table (
  window_key text,
  total_points integer,
  percentile integer,
  pick_points integer,
  like_points integer
)
language sql
stable
security definer
set search_path = ''
as $$ select * from private.knower_highlights(auth.uid()) $$;

create function public.get_profile_knower_highlights(p_profile_id uuid)
returns table (
  window_key text,
  total_points integer,
  percentile integer,
  pick_points integer,
  like_points integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from private.knower_highlights(p_profile_id)
   where private.can_view_profile(auth.uid(), p_profile_id)
$$;

revoke all on function public.my_profile_knower_highlights() from public, anon;
revoke all on function public.get_profile_knower_highlights(uuid) from public, anon;
grant execute on function public.my_profile_knower_highlights() to authenticated;
grant execute on function public.get_profile_knower_highlights(uuid) to authenticated;
