-- Friends feed v2 (Friends tab on Home).
--
-- The feed now shows what a friend actually answered, not just that they did,
-- and keeps game results to the two moments worth a friend's attention:
--
--   take        a friend's answer to a prompt that has locked (or resolved), with the
--               take they posted alongside it, if any. `response` is {slot id: chosen
--               option ids}, in the order they chose them (a ranking keeps its order),
--               the same shape a take card draws from; `comment_id` and `reply_count`
--               locate the take's thread; `points` is their total once it resolves.
--   pick_made   a friend answered a prompt that is still open. The answer stays out of
--               the feed until the lock, exactly as it stays out of the prompt thread
--               (prompts.revealed_responses, 0103): nobody can copy a pick.
--   win         a friend won a multiplayer match (first place in an arcade or party
--               run of two or more players; a tie for first gives each tied player the
--               win, as on the Gamer board, 0192). `opponents` names the other players
--               who are friends of the caller, `opponent_you` says the caller was one
--               of them and `opponent_count` is everyone else in the match.
--   high_score  a friend raised their own best in a solo game: Higher or Lower's
--               longest streak, or QB Season Builder's best season (`mode` says which
--               board). Their first score counts, because it is the first best.
--               `friend_rank` of `friend_count` places the new best among the caller
--               and their friends.
--
-- It replaces pick_result (folded into take) and match_result (solo and lost matches
-- no longer appear). Same 30-day window and p_before paging as 0188.

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
  picks as (
    select r.profile_id, r.post_id, min(r.created_at) as at, sum(r.points_earned)::integer as points
      from public.prompt_responses r
      join friends on friends.id = r.profile_id
     where r.created_at > now() - interval '30 days'
     group by r.profile_id, r.post_id
  ),
  events as (
    select case when posts.lock_at <= now() or posts.status = 'resolved' then 'take' else 'pick_made' end as event_type,
           picks.at as occurred_at, picks.profile_id as actor_id,
           posts.id as post_id, posts.caption as post_caption,
           tk.body as take_body, tk.id as comment_id,
           (select count(*)::integer from public.prompt_comments rp where rp.parent_comment_id = tk.id) as reply_count,
           case when posts.lock_at <= now() or posts.status = 'resolved' then
             (select jsonb_object_agg(r.slot_id, to_jsonb(r.chosen_option_ids))
                from public.prompt_responses r
               where r.post_id = posts.id and r.profile_id = picks.profile_id)
           end as response,
           case when posts.status = 'resolved' then picks.points end as points,
           null::uuid as match_id, null::text as game, null::smallint as placement,
           null::numeric as raw_score, null::text as run_mode, null::text as mode,
           null::text[] as opponents, null::boolean as opponent_you, null::integer as opponent_count,
           null::integer as friend_rank, null::integer as friend_count
      from picks
      join public.prompt_posts posts on posts.id = picks.post_id and posts.status <> 'void'
      left join lateral (
        select c.id, c.body from public.prompt_comments c
         where c.post_id = posts.id and c.author_id = picks.profile_id
           and c.posted_with_pick and c.parent_comment_id is null
           and (posts.lock_at <= now() or posts.status = 'resolved')
         order by c.created_at limit 1
      ) tk on true

    union all

    select 'win', m.ended_at, mp.user_id,
           null, null, null, null, null, null, null,
           m.id, m.game, mp.placement, mp.raw_score, run.mode::text, null,
           (select array_agg(p.display_name order by o.placement, p.display_name)
              from public.match_players o
              join public.profiles p on p.id = o.user_id
              join friends f on f.id = o.user_id
             where o.match_id = m.id and o.user_id <> mp.user_id),
           exists (select 1 from public.match_players o where o.match_id = m.id and o.user_id = v_me and o.user_id <> mp.user_id),
           (select count(*)::integer from public.match_players o where o.match_id = m.id and o.user_id <> mp.user_id),
           null, null
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
