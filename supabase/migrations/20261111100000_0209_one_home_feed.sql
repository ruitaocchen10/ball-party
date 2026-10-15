-- Home is one feed (0209 follow-up): friends' answers to prompts no longer have their own
-- cards, so friend_activity stops returning take and pick_made events. A prompt's card says
-- which friends answered it instead, via friends_who_answered below. What remains are the
-- game moments: multiplayer wins and new solo high scores. Same 30-day window and p_before
-- paging as 0194.

drop function public.friend_activity(integer, timestamptz);

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
  take_body text,
  comment_id uuid,
  reply_count integer,
  response jsonb,
  points integer,
  match_id uuid,
  game text,
  placement smallint,
  raw_score numeric,
  run_mode text,
  mode text,
  opponents text[],
  opponent_you boolean,
  opponent_count integer,
  friend_rank integer,
  friend_count integer
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
  circle as (
    select v_me as id
    union
    select friends.id from friends
  ),
  events as (
    select 'win'::text as event_type, m.ended_at as occurred_at, mp.user_id as actor_id,
           null::uuid as post_id, null::text as post_caption, null::text as take_body, null::uuid as comment_id,
           null::integer as reply_count, null::jsonb as response, null::integer as points,
           m.id as match_id, m.game, mp.placement, mp.raw_score, run.mode::text as run_mode, null::text as mode,
           (select array_agg(p.display_name order by o.placement, p.display_name)
              from public.match_players o
              join public.profiles p on p.id = o.user_id
              join friends f on f.id = o.user_id
             where o.match_id = m.id and o.user_id <> mp.user_id) as opponents,
           exists (select 1 from public.match_players o where o.match_id = m.id and o.user_id = v_me and o.user_id <> mp.user_id) as opponent_you,
           (select count(*)::integer from public.match_players o where o.match_id = m.id and o.user_id <> mp.user_id) as opponent_count,
           null::integer as friend_rank, null::integer as friend_count
      from public.match_players mp
      join friends on friends.id = mp.user_id
      join public.matches m on m.id = mp.match_id
      join public.runs run on run.id = m.run_id
     where mp.placement = 1
       and run.mode in ('arcade'::public.run_mode, 'party'::public.run_mode)
       and m.status = 'complete'::public.match_status
       and m.ended_at is not null
       and m.ended_at > now() - interval '30 days'
       and (select count(*) from public.match_players o where o.match_id = m.id) >= 2

    union all

    select 'high_score', st.updated_at, st.user_id,
           null, null, null, null, null, null, null,
           null, 'higher_or_lower', null, st.all_time_high::numeric, null, null,
           null, null, null,
           (select count(*)::integer + 1 from public.higher_or_lower_player_stats o
             join circle on circle.id = o.user_id where o.all_time_high > st.all_time_high),
           (select count(*)::integer from public.higher_or_lower_player_stats o
             join circle on circle.id = o.user_id where o.all_time_high > 0)
      from public.higher_or_lower_player_stats st
      join friends on friends.id = st.user_id
     where st.all_time_high > 0
       and st.updated_at > now() - interval '30 days'

    union all

    select 'high_score', st.updated_at, st.user_id,
           null, null, null, null, null, null, null,
           null, 'qb_season_builder', null, st.best_score, null, st.mode,
           null, null, null,
           (select count(*)::integer + 1 from public.qb_season_builder_player_stats o
             join circle on circle.id = o.user_id where o.mode = st.mode and o.best_score > st.best_score),
           (select count(*)::integer from public.qb_season_builder_player_stats o
             join circle on circle.id = o.user_id where o.mode = st.mode)
      from public.qb_season_builder_player_stats st
      join friends on friends.id = st.user_id
     where st.updated_at > now() - interval '30 days'
  )
  select events.event_type, events.occurred_at, events.actor_id,
         friends.username, friends.display_name, friends.avatar_url,
         events.post_id, events.post_caption, events.take_body, events.comment_id, events.reply_count,
         events.response, events.points,
         events.match_id, events.game, events.placement, events.raw_score, events.run_mode, events.mode,
         events.opponents, events.opponent_you, events.opponent_count, events.friend_rank, events.friend_count
    from events
    join friends on friends.id = events.actor_id
   where p_before is null or events.occurred_at < p_before
   order by events.occurred_at desc, events.actor_id, events.event_type
   limit greatest(1, least(coalesce(p_limit, 30), 50));
end;
$$;

revoke all on function public.friend_activity(integer, timestamptz) from public, anon;
grant execute on function public.friend_activity(integer, timestamptz) to authenticated;

-- Which of the caller's friends answered each of the given prompts. Only the fact, never the
-- choice: a pick stays hidden until the lock (prompts.revealed_responses, 0103), and the
-- prompt's own thread is where the takes live. Newest answer first, per prompt.
create function public.friends_who_answered(p_post_ids uuid[])
returns table (
  post_id uuid,
  actor_id uuid,
  username text,
  display_name text,
  avatar_url text,
  answered_at timestamptz
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
  select r.post_id, p.id, p.username, p.display_name, p.avatar_url, min(r.created_at) as answered_at
    from public.prompt_responses r
    join public.friendships f
      on f.status = 'accepted'
     and v_me in (f.requester_id, f.addressee_id)
     and r.profile_id = case when f.requester_id = v_me then f.addressee_id else f.requester_id end
    join public.profiles p on p.id = r.profile_id and p.deleted_at is null
   where r.post_id = any (p_post_ids)
   group by r.post_id, p.id, p.username, p.display_name, p.avatar_url
   order by r.post_id, min(r.created_at) desc;
end;
$$;

revoke all on function public.friends_who_answered(uuid[]) from public, anon;
grant execute on function public.friends_who_answered(uuid[]) to authenticated;
