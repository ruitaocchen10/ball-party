-- Friends activity feed (Friends, BPP-3).
--
-- friend_activity() returns the caller's friends' recent events, newest
-- first. Activity is visible to friends by default; there is no per-user
-- opt-out in v1 (a private profile hides the profile body, not the feed).
-- The feed shows THAT a friend acted, never what they picked: a pick event
-- carries the prompt and time but not the chosen options, so a friend's
-- answer can't be read off the feed before a prompt locks.
--
-- A small fixed set of event types:
--   pick_made     a friend answered a prompt (any non-void post)
--   pick_result   a prompt they answered was resolved: points_earned total
--   match_result  a friend finished a match: game, placement, score, run mode
--
-- Only the last 30 days are considered, and results page with p_before (the
-- occurred_at of the last row of the previous page). Guests have no friends
-- and get guests_cannot_have_friends.

create function public.friend_activity(p_limit integer default 30, p_before timestamptz default null)
returns table (
  event_type text,
  occurred_at timestamptz,
  actor_id uuid,
  username text,
  display_name text,
  avatar_url text,
  post_id uuid,
  post_caption text,
  points integer,
  match_id uuid,
  game text,
  placement smallint,
  raw_score numeric,
  run_mode text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  return query
  with friends as (
    select p.id, p.username, p.display_name, p.avatar_url
      from public.friendships f
      join public.profiles p
        on p.id = case when f.requester_id = v_me then f.addressee_id else f.requester_id end
     where f.status = 'accepted'
       and v_me in (f.requester_id, f.addressee_id)
       and p.deleted_at is null
  ),
  picks as (
    select r.profile_id, r.post_id, min(r.created_at) as at
      from public.prompt_responses r
      join friends on friends.id = r.profile_id
     where r.created_at > now() - interval '30 days'
     group by r.profile_id, r.post_id
  ),
  events as (
    select 'pick_made'::text as event_type, picks.at as occurred_at, picks.profile_id as actor_id,
           posts.id as post_id, posts.caption as post_caption, null::integer as points,
           null::uuid as match_id, null::text as game, null::smallint as placement,
           null::numeric as raw_score, null::text as run_mode
      from picks
      join public.prompt_posts posts on posts.id = picks.post_id and posts.status <> 'void'

    union all

    select 'pick_result', posts.resolved_at, r.profile_id,
           posts.id, posts.caption, sum(r.points_earned)::integer,
           null, null, null, null, null
      from public.prompt_responses r
      join friends on friends.id = r.profile_id
      join public.prompt_posts posts on posts.id = r.post_id and posts.status = 'resolved'
     where r.points_earned is not null
       and posts.resolved_at > now() - interval '30 days'
     group by r.profile_id, posts.id, posts.caption, posts.resolved_at

    union all

    select 'match_result', m.ended_at, mp.user_id,
           null, null, null,
           m.id, m.game, mp.placement, mp.raw_score, run.mode::text
      from public.match_players mp
      join friends on friends.id = mp.user_id
      join public.matches m on m.id = mp.match_id
      join public.runs run on run.id = m.run_id
     where m.status = 'complete'::public.match_status
       and m.ended_at is not null
       and m.ended_at > now() - interval '30 days'
  )
  select events.event_type, events.occurred_at, events.actor_id,
         friends.username, friends.display_name, friends.avatar_url,
         events.post_id, events.post_caption, events.points,
         events.match_id, events.game, events.placement, events.raw_score, events.run_mode
    from events
    join friends on friends.id = events.actor_id
   where p_before is null or events.occurred_at < p_before
   order by events.occurred_at desc, events.actor_id, events.event_type
   limit greatest(1, least(coalesce(p_limit, 30), 50));
end;
$$;

revoke all on function public.friend_activity(integer, timestamptz) from public, anon;
grant execute on function public.friend_activity(integer, timestamptz) to authenticated;
