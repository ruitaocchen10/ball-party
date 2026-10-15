-- Ranking lists: names for the players in a list.
--
-- A list stores player ids (see 0210), so a client needs a way to turn ids into
-- names and faces. This returns the same identity fields as
-- prompts.search_players (0172) and nothing else, for the ids asked about.
-- Teams need no lookup: their codes are the 32 nflverse codes the clients know.

create function public.ranking_players(p_ids text[])
returns table (
  player_id    text,
  display_name text,
  "position"   text,
  team         text,
  headshot_url text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.player_id, p.display_name, p."position", p.team, p.headshot_url
    from prompts_private.nfl_players p
   where auth.uid() is not null
     and p.player_id = any (p_ids[1:100]);
$$;

revoke all on function public.ranking_players(text[]) from public, anon;
grant execute on function public.ranking_players(text[]) to authenticated;

-- Ranking lists: the home feed's list updates.
--
-- The published edits of the viewer and their friends, newest first, each with
-- the list it replaced so the card can show what moved. Update cards are
-- friends-only (0211), so the audience is the viewer plus accepted friends.
-- With p_post_id it returns that one card, if the viewer may see it.
create function public.friend_list_updates(p_limit integer default 20, p_before timestamptz default null, p_post_id uuid default null)
returns table (
  post_id      uuid,
  author_id    uuid,
  username     text,
  display_name text,
  avatar_url   text,
  kind         text,
  label        text,
  item_kind    text,
  version_no   integer,
  note         text,
  created_at   timestamptz,
  items        text[],
  prev_items   text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.ranking_viewer();
begin
  return query
    select v.update_post_id, pr.id, pr.username, pr.display_name, pr.avatar_url,
           l.kind, k.label, k.item_kind, v.version_no, v.note, v.created_at,
           private.ranking_items(v.id),
           (select private.ranking_items(x.id) from public.ranking_list_versions x
             where x.list_id = l.id and x.version_no = v.version_no - 1)
      from public.ranking_list_versions v
      join public.ranking_lists l on l.id = v.list_id
      join public.ranking_list_kinds k on k.id = l.kind
      join public.profiles pr on pr.id = l.profile_id
     where v.update_post_id is not null
       and pr.deleted_at is null
       and (pr.id = v_me or private.are_friends(v_me, pr.id))
       and (p_before is null or v.created_at < p_before)
       and (p_post_id is null or v.update_post_id = p_post_id)
     order by v.created_at desc
     limit least(greatest(coalesce(p_limit, 20), 1), 50);
end;
$$;

revoke all on function public.friend_list_updates(integer, timestamptz, uuid) from public, anon;
grant execute on function public.friend_list_updates(integer, timestamptz, uuid) to authenticated;
