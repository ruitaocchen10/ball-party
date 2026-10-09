-- Gamer leaderboards (BPP-2).
--
-- Two kinds of board, both ranked entirely here so clients never rank anything:
--
--   gamer_leaderboard / my_gamer_standing
--     Multiplayer wins. A win is placement = 1 in a completed match whose run is
--     not solo and that had at least two players (a one-person party match would
--     otherwise hand out free wins). A tie for first shares the win, because
--     placement already gives tied scores the better rank. Windows are the same
--     rolling 7/30/365 days as Ball Knower, on the match's ended_at.
--
--   solo_leaderboard / my_solo_standing
--     One all-time board per solo game, ranked on each player's best single run:
--       higher_or_lower   best solo streak (higher_or_lower_player_stats)
--       qb_season_builder best score, per mode, 'visible' or 'hidden', which are
--                         never compared with each other (qb_season_builder_player_stats)
--     Both stats tables are own-row RLS, so the boards read them from these
--     security definer functions. No time windows: a personal best is all-time.
--
-- Same rules as the Ball Knower board: accounts only (guests and deleted accounts
-- never rank, and a private profile still ranks), 'all' or 'friends' scope, ties
-- share a rank, and a row's username is withheld across a block so it never links
-- to a profile the viewer cannot open.

-- ------------------------------------------------------------ shared helpers --

create function private.leaderboard_username(p_profile uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (
      select 1 from public.friendships f
       where f.status = 'blocked'
         and ((f.requester_id = auth.uid() and f.addressee_id = p_profile)
           or (f.requester_id = p_profile and f.addressee_id = auth.uid()))
    ) then null
    else (select p.username from public.profiles p where p.id = p_profile)
  end;
$$;
revoke all on function private.leaderboard_username(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------- multiplayer wins --

create function private.gamer_min_wins()
returns integer
language sql
immutable
set search_path = ''
as $$ select 1 $$;

-- Every player's wins and games played in the window, with no eligibility or
-- floor applied.
create function private.gamer_totals(p_window text)
returns table (profile_id uuid, wins integer, games_played integer)
language sql
stable
security definer
set search_path = ''
as $$
  with seated as (
    select m.id as match_id, count(*) as players
      from public.matches m
      join public.runs r on r.id = m.run_id
      join public.match_players mp on mp.match_id = m.id
     where m.status = 'complete'::public.match_status
       and m.ended_at is not null
       and r.mode <> 'solo'::public.run_mode
       and (
         p_window = 'lifetime'
         or m.ended_at >= now() - case p_window
           when 'week'  then interval '7 days'
           when 'month' then interval '30 days'
           when 'year'  then interval '365 days'
         end
       )
     group by m.id
    having count(*) >= 2
  )
  select mp.user_id,
         (count(*) filter (where mp.placement = 1))::integer,
         count(*)::integer
    from seated
    join public.match_players mp on mp.match_id = seated.match_id
   group by mp.user_id;
$$;

create function private.gamer_cohort(p_window text, p_scope text, p_viewer uuid)
returns table (
  profile_id uuid,
  display_name text,
  avatar_url text,
  wins integer,
  games_played integer,
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
           totals.wins, totals.games_played
    from private.gamer_totals(p_window) totals
    join public.profiles profiles on profiles.id = totals.profile_id
    where profiles.deleted_at is null
      and not profiles.is_guest
      and totals.wins >= private.gamer_min_wins()
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
    eligible.wins,
    eligible.games_played,
    (rank() over (order by eligible.wins desc))::integer,
    (count(*) over ())::integer
  from eligible;
$$;

revoke all on function private.gamer_totals(text) from public, anon, authenticated;
revoke all on function private.gamer_min_wins() from public, anon, authenticated;
revoke all on function private.gamer_cohort(text, text, uuid) from public, anon, authenticated;

create function public.gamer_leaderboard(
  p_window text,
  p_limit integer default 50,
  p_scope text default 'all'
)
returns table (
  rank integer,
  profile_id uuid,
  display_name text,
  avatar_url text,
  wins integer,
  games_played integer,
  is_me boolean,
  ranked_count integer,
  username text
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
           cohort.wins, cohort.games_played,
           cohort.profile_id = auth.uid(), cohort.ranked_count,
           private.leaderboard_username(cohort.profile_id)
    from private.gamer_cohort(p_window, p_scope, auth.uid()) cohort
    order by cohort.rank, cohort.display_name, cohort.profile_id
    limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

-- status: 'ranked' (on the board) or 'unranked' (under the win floor, which
-- includes no games at all). Wins and games are the caller's own either way;
-- ranked_count is the size of the chosen scope's board.
create function public.my_gamer_standing(p_window text, p_scope text default 'all')
returns table (
  status text,
  rank integer,
  wins integer,
  games_played integer,
  ranked_count integer,
  min_wins integer
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
      select totals.wins, totals.games_played
      from private.gamer_totals(p_window) totals
      where totals.profile_id = v_me
    ),
    cohort as (
      select * from private.gamer_cohort(p_window, p_scope, v_me)
    )
    select
      case when me_ranked.profile_id is not null then 'ranked' else 'unranked' end,
      me_ranked.rank,
      coalesce((select mine.wins from mine), 0),
      coalesce((select mine.games_played from mine), 0),
      (select count(*)::integer from cohort),
      private.gamer_min_wins()
    from (select 1) one
    left join cohort me_ranked on me_ranked.profile_id = v_me;
end;
$$;

revoke all on function public.gamer_leaderboard(text, integer, text) from public, anon;
revoke all on function public.my_gamer_standing(text, text) from public, anon;
grant execute on function public.gamer_leaderboard(text, integer, text) to authenticated;
grant execute on function public.my_gamer_standing(text, text) to authenticated;

-- ------------------------------------------------------------- solo bests --

-- Every player's best for one solo board, with no eligibility applied beyond
-- "has a recorded best". p_mode is the QB Season Builder mode and must be null
-- for every other game, so a new solo game cannot be asked for by accident.
create function private.solo_bests(p_game text, p_mode text)
returns table (profile_id uuid, best numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_game = 'higher_or_lower' then
    if p_mode is not null then
      raise exception 'invalid_mode' using errcode = '22023';
    end if;
    return query
      select s.user_id, s.all_time_high::numeric
        from public.higher_or_lower_player_stats s
       where s.all_time_high > 0;
  elsif p_game = 'qb_season_builder' then
    if p_mode is null or p_mode not in ('visible', 'hidden') then
      raise exception 'invalid_mode' using errcode = '22023';
    end if;
    return query
      select s.user_id, s.best_score
        from public.qb_season_builder_player_stats s
       where s.mode = p_mode;
  else
    raise exception 'invalid_game' using errcode = '22023';
  end if;
end;
$$;

create function private.solo_cohort(p_game text, p_mode text, p_scope text, p_viewer uuid)
returns table (
  profile_id uuid,
  display_name text,
  avatar_url text,
  best numeric,
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
    select bests.profile_id, profiles.display_name, profiles.avatar_url, bests.best
    from private.solo_bests(p_game, p_mode) bests
    join public.profiles profiles on profiles.id = bests.profile_id
    where profiles.deleted_at is null
      and not profiles.is_guest
      and (
        p_scope = 'all'
        or bests.profile_id = p_viewer
        or bests.profile_id in (select id from friend_ids)
      )
  )
  select
    eligible.profile_id,
    eligible.display_name,
    eligible.avatar_url,
    eligible.best,
    (rank() over (order by eligible.best desc))::integer,
    (count(*) over ())::integer
  from eligible;
$$;

revoke all on function private.solo_bests(text, text) from public, anon, authenticated;
revoke all on function private.solo_cohort(text, text, text, uuid) from public, anon, authenticated;

create function public.solo_leaderboard(
  p_game text,
  p_mode text default null,
  p_limit integer default 50,
  p_scope text default 'all'
)
returns table (
  rank integer,
  profile_id uuid,
  display_name text,
  avatar_url text,
  best_score numeric,
  is_me boolean,
  ranked_count integer,
  username text
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
  if p_scope is null or p_scope not in ('all', 'friends') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;
  if p_scope = 'friends' then
    perform private.friend_caller();
  end if;

  return query
    select cohort.rank, cohort.profile_id, cohort.display_name, cohort.avatar_url,
           cohort.best,
           cohort.profile_id = auth.uid(), cohort.ranked_count,
           private.leaderboard_username(cohort.profile_id)
    from private.solo_cohort(p_game, p_mode, p_scope, auth.uid()) cohort
    order by cohort.rank, cohort.display_name, cohort.profile_id
    limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

-- status: 'ranked' or 'unranked' (the caller has no recorded best on this
-- board). best_score is the caller's own best either way, null when there is none.
create function public.my_solo_standing(
  p_game text,
  p_mode text default null,
  p_scope text default 'all'
)
returns table (
  status text,
  rank integer,
  best_score numeric,
  ranked_count integer
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
  if p_scope is null or p_scope not in ('all', 'friends') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;
  if p_scope = 'friends' then
    perform private.friend_caller();
  end if;

  return query
    with mine as (
      select bests.best from private.solo_bests(p_game, p_mode) bests where bests.profile_id = v_me
    ),
    cohort as (
      select * from private.solo_cohort(p_game, p_mode, p_scope, v_me)
    )
    select
      case when me_ranked.profile_id is not null then 'ranked' else 'unranked' end,
      me_ranked.rank,
      (select mine.best from mine),
      (select count(*)::integer from cohort)
    from (select 1) one
    left join cohort me_ranked on me_ranked.profile_id = v_me;
end;
$$;

revoke all on function public.solo_leaderboard(text, text, integer, text) from public, anon;
revoke all on function public.my_solo_standing(text, text, text) from public, anon;
grant execute on function public.solo_leaderboard(text, text, integer, text) to authenticated;
grant execute on function public.my_solo_standing(text, text, text) to authenticated;
