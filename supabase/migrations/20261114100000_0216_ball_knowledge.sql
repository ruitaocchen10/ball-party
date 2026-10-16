-- Ball knowledge (BPP-39).
--
-- A player can give a take a ball (+1) or take one away (-1). The take's author
-- earns the net: balls are added to the Ball Knower points, so Ball Knower is the
-- one "ball knowledge" score. Picks and balls both feed it.
--
-- A take is a top-level prompt_comments row. That covers every answer (0208),
-- including picks-only ones, and the friends-only list update cards (0211).
-- Replies are not reactable.
--
-- Rules, all enforced here:
--   - a real account (not a guest) reacts; anyone may like;
--   - only an accepted friend of the author may dislike;
--   - no reacting to your own take, or to a take you cannot see (a friends-only
--     update card, or anyone with a block between you and the author);
--   - one reaction per player per take; the same value again is a no-op, the
--     other value switches it, and 0 removes it.
--
-- Windows (week, month, year, lifetime) count a ball when it was last given or
-- switched, not when the take was written. The 3-scored-pick floor on the board
-- is unchanged, so balls alone never put a player on it.

-- -------------------------------------------------------------- table --

create table public.take_reactions (
  comment_id uuid not null references public.prompt_comments (id) on delete cascade,
  reactor_id uuid not null references public.profiles (id) on delete cascade,
  value      smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now(),
  -- Moves when the reaction is switched, which is what the windows read.
  updated_at timestamptz not null default now(),
  primary key (comment_id, reactor_id)
);

create index take_reactions_updated_at on public.take_reactions (updated_at);

-- Who reacted is not public. Reads go through take_reaction_summary and the
-- score functions, which are definer functions.
alter table public.take_reactions enable row level security;
revoke all on table public.take_reactions from public, anon, authenticated;

-- ------------------------------------------------------------- helpers --

-- Whether the caller may see and react to this take: a top-level take on a post
-- the caller can read, with no block between the caller and its author.
create function private.can_react_to_take(p_comment uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.prompt_comments c
      join public.prompt_posts p on p.id = c.post_id
     where c.id = p_comment
       and c.parent_comment_id is null
       and (p.template_kind <> 'ranking_update' or public.can_see_ranking_update(p.author_id))
       and not exists (
         select 1 from public.friendships f
          where f.status = 'blocked'
            and least(f.requester_id, f.addressee_id) = least(p_viewer, c.author_id)
            and greatest(f.requester_id, f.addressee_id) = greatest(p_viewer, c.author_id)
       )
  );
$$;
revoke all on function private.can_react_to_take(uuid, uuid) from public, anon, authenticated;

-- --------------------------------------------------------------- write --

-- p_value: 1 (ball), -1 (take a ball away) or 0 (remove my reaction).
-- Returns the take's new net and the caller's reaction.
create function public.react_to_take(p_comment_id uuid, p_value smallint)
returns table (net_balls integer, my_reaction smallint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me     uuid := auth.uid();
  v_profile public.profiles;
  v_author uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_profile from public.profiles where id = v_me;
  if not found or v_profile.deleted_at is not null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_profile.is_guest then
    raise exception 'guests_cannot_react' using errcode = '42501';
  end if;
  if p_value is null or p_value not in (-1, 0, 1) then
    raise exception 'invalid_reaction' using errcode = '22023';
  end if;

  select author_id into v_author from public.prompt_comments where id = p_comment_id;
  if v_author is null or not private.can_react_to_take(p_comment_id, v_me) then
    raise exception 'take_not_found' using errcode = 'P0002';
  end if;
  if v_author = v_me then
    raise exception 'cannot_react_to_own_take' using errcode = '42501';
  end if;
  if p_value = -1 and not private.are_friends(v_me, v_author) then
    raise exception 'dislike_friends_only' using errcode = '42501';
  end if;

  if p_value = 0 then
    delete from public.take_reactions where comment_id = p_comment_id and reactor_id = v_me;
  else
    insert into public.take_reactions (comment_id, reactor_id, value)
    values (p_comment_id, v_me, p_value)
    on conflict (comment_id, reactor_id) do update
      set value = excluded.value, updated_at = now()
      where public.take_reactions.value <> excluded.value;
  end if;

  return query
    select coalesce(sum(r.value), 0)::integer,
           coalesce((select r2.value from public.take_reactions r2
                      where r2.comment_id = p_comment_id and r2.reactor_id = v_me), 0)::smallint
      from public.take_reactions r
     where r.comment_id = p_comment_id;
end;
$$;

-- ---------------------------------------------------------------- read --

-- The net, the caller's own reaction and what the caller may do, for a page of
-- takes. A take the caller cannot see is left out. can_like and can_dislike are
-- the server's answer, so a client never works the rules out itself.
create function public.take_reaction_summary(p_comment_ids uuid[])
returns table (
  comment_id uuid,
  net_balls integer,
  my_reaction smallint,
  can_like boolean,
  can_dislike boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select p.id
      from public.profiles p
     where p.id = auth.uid() and p.deleted_at is null and not p.is_guest
  )
  select
    c.id,
    coalesce((select sum(r.value) from public.take_reactions r where r.comment_id = c.id), 0)::integer,
    coalesce((select r.value from public.take_reactions r
               where r.comment_id = c.id and r.reactor_id = (select id from me)), 0)::smallint,
    (select id from me) is not null and c.author_id <> (select id from me),
    (select id from me) is not null and c.author_id <> (select id from me)
      and private.are_friends((select id from me), c.author_id)
  from public.prompt_comments c
 where c.id = any (p_comment_ids[1:500])
   and private.can_react_to_take(c.id, coalesce((select id from me), '00000000-0000-0000-0000-000000000000'::uuid));
$$;

-- --------------------------------------------------------------- score --

-- Pick points plus net balls. scored_picks still counts resolved picks only.
-- Same signature as 0181 so every caller (the board, standing, highlights)
-- picks the balls up without changing.
create or replace function private.ball_knower_totals(p_window text)
returns table (profile_id uuid, total_points integer, scored_picks integer)
language sql
stable
security definer
set search_path = ''
as $$
  with picks as (
    select responses.profile_id,
           sum(responses.points_earned)::integer as points,
           count(*)::integer as picks
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
         (coalesce(picks.points, 0) + coalesce(balls.net, 0))::integer,
         coalesce(picks.picks, 0)
    from picks
    full join balls on balls.profile_id = picks.profile_id;
$$;
revoke all on function private.ball_knower_totals(text) from public, anon, authenticated;

-- The profile's per-window points and percentile (0186) read the same totals,
-- so the profile number matches the board.
create or replace function private.knower_highlights(p_profile uuid)
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
    select unnest(array['lifetime', 'year', 'month', 'week']) as window_key
  ),
  totals as (
    select windows.window_key, t.profile_id, t.total_points
      from windows
     cross join lateral private.ball_knower_totals(windows.window_key) t
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
    on totals.window_key = windows.window_key and totals.profile_id = p_profile
  left join ranked
    on ranked.window_key = windows.window_key and ranked.profile_id = p_profile
  order by case windows.window_key when 'lifetime' then 1 when 'year' then 2 when 'month' then 3 when 'week' then 4 end;
$$;
revoke all on function private.knower_highlights(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------- grants --

revoke all on function public.react_to_take(uuid, smallint) from public, anon;
grant execute on function public.react_to_take(uuid, smallint) to authenticated;
revoke all on function public.take_reaction_summary(uuid[]) from public;
grant execute on function public.take_reaction_summary(uuid[]) to anon, authenticated;
