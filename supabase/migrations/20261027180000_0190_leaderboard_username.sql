-- Return each leaderboard row's username (Friends, BPP-3) so clients can link a
-- row to /u/<username>. get_profile looks players up by username only, and
-- profiles are not readable by other players, so the board is the one place
-- that can hand the username out. It is already public to signed-in accounts.
--
-- Username comes back null when either side of the pair has blocked the other,
-- so a row never links a viewer to a profile they cannot open. Guests have no
-- username either. The cohort helper is unchanged; the join happens here.
--
-- The return type changes, so the function is dropped and recreated.

drop function public.ball_knower_leaderboard(text, integer, text);

create function public.ball_knower_leaderboard(
  p_window text,
  p_limit integer default 50,
  p_scope text default 'all'
)
returns table (
  rank integer,
  profile_id uuid,
  display_name text,
  avatar_url text,
  total_points integer,
  scored_picks integer,
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
           cohort.total_points, cohort.scored_picks,
           cohort.profile_id = auth.uid(), cohort.ranked_count,
           case
             when exists (
               select 1 from public.friendships f
                where f.status = 'blocked'
                  and ((f.requester_id = auth.uid() and f.addressee_id = cohort.profile_id)
                    or (f.requester_id = cohort.profile_id and f.addressee_id = auth.uid()))
             ) then null
             else profiles.username
           end
    from private.ball_knower_cohort(p_window, p_scope, auth.uid()) cohort
    join public.profiles profiles on profiles.id = cohort.profile_id
    order by cohort.rank, cohort.display_name, cohort.profile_id
    limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

revoke all on function public.ball_knower_leaderboard(text, integer, text) from public, anon;
grant execute on function public.ball_knower_leaderboard(text, integer, text) to authenticated;
