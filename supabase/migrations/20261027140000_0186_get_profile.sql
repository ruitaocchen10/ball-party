-- Reading other players' profiles (Friends, BPP-3).
--
-- profiles RLS stays own / co-player / prompt-author only. A broad select
-- policy would expose is_guest, is_private, deleted_at and the rest to every
-- signed-in account, so other people's profiles are read through these RPCs,
-- which return a fixed set of safe columns.
--
-- Visibility: a profile body can be opened by its owner, by anyone when the
-- profile is public (the default), and only by friends when is_private.
-- Header facts (username, display name, avatar) are returned either way so a
-- private player can still be found and asked to be a friend. Signed-out
-- visitors have no execute grant, guests get nothing, and a player who
-- blocked the viewer is not found at all.
--
-- get_profile finds a player by username (rate limited like friend search,
-- since it is also a username lookup) and says whether the body is open.
-- The body RPCs take the profile_id it returned: ids are unguessable, so they
-- are not a second way to probe for usernames.

-- The body queries, parameterised on whose profile, so the "my" and "their"
-- versions are one implementation.
create function private.knower_highlights(p_profile uuid)
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
    on totals.window_key = windows.window_key and totals.profile_id = p_profile
  left join ranked
    on ranked.window_key = windows.window_key and ranked.profile_id = p_profile
  order by case windows.window_key when 'lifetime' then 1 when 'year' then 2 when 'month' then 3 when 'week' then 4 end;
$$;

create function private.match_history(p_profile uuid)
returns table (
  match_id uuid,
  game text,
  ended_at timestamptz,
  placement smallint,
  raw_score numeric,
  mode public.run_mode
)
language sql
stable
security definer
set search_path = ''
as $$
  select mp.match_id, m.game, m.ended_at, mp.placement, mp.raw_score, r.mode
    from public.match_players mp
    join public.matches m on m.id = mp.match_id
    join public.runs r on r.id = m.run_id
   where mp.user_id = p_profile
     and m.status = 'complete'::public.match_status
     and m.ended_at is not null
   order by m.ended_at desc;
$$;

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
as $$ select * from private.knower_highlights(auth.uid()) $$;

create or replace function public.my_match_history()
returns table (
  match_id uuid,
  game text,
  ended_at timestamptz,
  placement smallint,
  raw_score numeric,
  mode public.run_mode
)
language sql
stable
security definer
set search_path = ''
as $$ select * from private.match_history(auth.uid()) $$;

-- ------------------------------------------------------------- visibility --

-- True when p_viewer (a real, signed-in account) may open p_target's body.
create function private.can_view_profile(p_viewer uuid, p_target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (select 1 from public.profiles v where v.id = p_viewer and not v.is_guest and v.deleted_at is null)
    and exists (
      select 1 from public.profiles t
       where t.id = p_target and not t.is_guest and t.deleted_at is null
         and (t.id = p_viewer or not t.is_private or private.are_friends(p_viewer, p_target))
    )
    and not exists (
      select 1 from public.friendships f
       where f.status = 'blocked' and f.requester_id = p_target and f.addressee_id = p_viewer
    );
$$;
revoke all on function private.knower_highlights(uuid) from public, anon, authenticated;
revoke all on function private.match_history(uuid) from public, anon, authenticated;
revoke all on function private.can_view_profile(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------- RPC --

-- One row, or none when: not signed in as a real account, no such username,
-- the owner is a guest/deleted, or the owner blocked the viewer.
-- relationship: self | none | friends | outgoing | incoming | blocked.
create function public.get_profile(p_username text)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  is_private boolean,
  relationship text,
  can_view boolean,
  member_since timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- Guests and deleted accounts get nothing, not an error.
  if not exists (select 1 from public.profiles v where v.id = v_me and not v.is_guest and v.deleted_at is null) then
    return;
  end if;
  perform private.rate_limit_hit('get_profile', 120, interval '1 minute');

  if p_username is null or p_username !~ '^[A-Za-z0-9_]{3,20}$' then
    return;
  end if;

  return query
    select p.id, p.username, p.display_name, p.avatar_url, p.is_private,
           case when p.id = v_me then 'self' else private.friend_relationship(v_me, p.id) end,
           private.can_view_profile(v_me, p.id),
           p.created_at
      from public.profiles p
     where lower(p.username) = lower(p_username)
       and not p.is_guest and p.deleted_at is null
       and not exists (
         select 1 from public.friendships f
          where f.status = 'blocked' and f.requester_id = p.id and f.addressee_id = v_me
       );
end;
$$;

-- Body reads: rows only when get_profile would say can_view for this viewer.
create function public.get_profile_knower_highlights(p_profile_id uuid)
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
  select * from private.knower_highlights(p_profile_id)
   where private.can_view_profile(auth.uid(), p_profile_id)
$$;

create function public.get_profile_match_history(p_profile_id uuid)
returns table (
  match_id uuid,
  game text,
  ended_at timestamptz,
  placement smallint,
  raw_score numeric,
  mode public.run_mode
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from private.match_history(p_profile_id)
   where private.can_view_profile(auth.uid(), p_profile_id)
$$;

revoke all on function public.get_profile(text) from public, anon;
revoke all on function public.get_profile_knower_highlights(uuid) from public, anon;
revoke all on function public.get_profile_match_history(uuid) from public, anon;
grant execute on function public.get_profile(text) to authenticated;
grant execute on function public.get_profile_knower_highlights(uuid) to authenticated;
grant execute on function public.get_profile_match_history(uuid) to authenticated;
