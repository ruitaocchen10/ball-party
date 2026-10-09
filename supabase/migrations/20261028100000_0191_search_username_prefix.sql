-- Username search matches by prefix, so the Friends tab can suggest players as
-- you type. Still not a way to browse accounts: a query needs at least 3
-- characters (the shortest username), results are capped at 8 and the rate
-- limit allows a typing burst but not a crawl.

drop function public.search_users_by_username(text);

create function public.search_users_by_username(p_query text)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  relationship text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  perform private.rate_limit_hit('friend_search', 120, interval '1 minute');

  -- Letters, digits and underscores only: no LIKE wildcards can get through,
  -- and starts_with() treats the text literally anyway.
  if p_query is null or p_query !~ '^[A-Za-z0-9_]{3,20}$' then
    return;
  end if;

  return query
    select p.id, p.username, p.display_name, p.avatar_url, private.friend_relationship(v_me, p.id)
      from public.profiles p
     where starts_with(lower(p.username), lower(p_query))
       and p.id <> v_me
       and not p.is_guest
       and p.deleted_at is null
       and not exists (
         select 1 from public.friendships f
          where f.status = 'blocked' and f.requester_id = p.id and f.addressee_id = v_me
       )
     order by (lower(p.username) = lower(p_query)) desc, lower(p.username)
     limit 8;
end;
$$;

revoke all on function public.search_users_by_username(text) from public, anon;
grant execute on function public.search_users_by_username(text) to authenticated;
