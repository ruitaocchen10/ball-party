-- Notification inbox backend (GitHub #169, part 1 of 4).
--
-- One server-side inbox that web and iOS both read. The server decides what is
-- a notification; clients only display. Three kinds of item:
--
--   friend_request  someone sent you a request. A notifications row, written by
--                   a trigger on public.friendships.
--   take_reply      someone replied to your take (a prompt comment). A
--                   notifications row, written by a trigger on
--                   public.prompt_comments. Replies to the same take coalesce
--                   into one row with a count.
--   room_invite     NOT stored here. Invites already have a real object
--                   (public.room_invites, 0189) with its own status and 24-hour
--                   life, so the inbox merges them in on read instead of
--                   copying them.
--
-- A notifications row is only a pointer (type + ref_id). What it shows, and
-- whether it still shows, is resolved on read from the source rows, so a
-- declined request, a deleted take or a block makes the item disappear without
-- anything having to clean up after it. The state shown for an item is computed
-- in private.inbox_items and nowhere else; the clients never decide whether a
-- request or an invite is still valid.
--
-- Pushes (#171, #172) will hang off the same rows. This migration sends nothing.
--
-- The table has RLS on and no write grants; clients use only the RPCs. The
-- recipient can SELECT their own rows so Realtime can nudge an open client, the
-- same shape as 0195. The event is only a nudge: clients re-read list_inbox.

create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  type         text not null check (type in ('friend_request', 'take_reply')),
  -- Who caused it. For a coalesced take_reply, the most recent replier.
  actor_id     uuid not null references public.profiles (id) on delete cascade,
  -- friend_request: friendships.id. take_reply: the take's prompt_comments.id.
  -- No foreign key: it points at different tables by type, and a vanished
  -- source simply hides the item on read.
  ref_id       uuid not null,
  -- take_reply: replies since the item was last read. Always 1 otherwise.
  reply_count  integer not null default 1 check (reply_count >= 1),
  created_at   timestamptz not null default now(),
  -- Last activity; the inbox sorts on this.
  updated_at   timestamptz not null default now(),
  read_at      timestamptz
);

create unique index notifications_item_idx on public.notifications (recipient_id, type, ref_id);
create index notifications_recipient_idx on public.notifications (recipient_id, updated_at desc);

alter table public.notifications enable row level security;
revoke all on table public.notifications from public, anon, authenticated;
grant select on table public.notifications to authenticated;
create policy notifications_select_recipient on public.notifications
  for select to authenticated using (recipient_id = auth.uid());

alter publication supabase_realtime add table public.notifications;

-- ---------------------------------------------------------------- helpers --

-- Either player has blocked the other. Blocks are rows in friendships.
create function private.blocked_either_way(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships
     where status = 'blocked'
       and least(requester_id, addressee_id) = least(p_a, p_b)
       and greatest(requester_id, addressee_id) = greatest(p_a, p_b)
  );
$$;

-- ---------------------------------------------------------------- writers --

-- A new pending request notifies the addressee. A request that is declined or
-- cancelled deletes the friendships row, so asking again is a fresh row with a
-- fresh id and a fresh notification. A pair with a block cannot have a pending
-- row (one row per pair), so no block check is needed here.
create function private.notify_friend_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'pending' then
    insert into public.notifications (recipient_id, type, actor_id, ref_id)
    values (new.addressee_id, 'friend_request', new.requester_id, new.id)
    on conflict (recipient_id, type, ref_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger friendships_notify
  after insert on public.friendships
  for each row execute function private.notify_friend_request();

-- A reply to a take notifies the take's author, unless it is their own reply or
-- there is a block between the two. One row per take: a further reply bumps the
-- count and the actor and marks it unread again. If the earlier replies were
-- already read, the count starts over, so it means "new since you looked".
create function private.notify_take_reply()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  if new.parent_comment_id is null then
    return new;
  end if;

  select author_id into v_owner from public.prompt_comments where id = new.parent_comment_id;
  if v_owner is null or v_owner = new.author_id
     or private.blocked_either_way(v_owner, new.author_id) then
    return new;
  end if;

  insert into public.notifications (recipient_id, type, actor_id, ref_id)
  values (v_owner, 'take_reply', new.author_id, new.parent_comment_id)
  on conflict (recipient_id, type, ref_id) do update
    set actor_id    = excluded.actor_id,
        reply_count = case when public.notifications.read_at is null
                           then public.notifications.reply_count + 1 else 1 end,
        read_at     = null,
        updated_at  = now();
  return new;
end;
$$;

create trigger prompt_comments_notify
  after insert on public.prompt_comments
  for each row execute function private.notify_take_reply();

-- ------------------------------------------------------------------ reader --

-- The caller's inbox: stored notifications and room invites, resolved against
-- their source rows. An item whose source is gone, whose actor deleted their
-- account, or whose actor is blocked either way, is not returned.
--
-- state:
--   friend_request  pending | accepted
--   take_reply      active
--   room_invite     pending | accepted | declined | expired
--                   (expired = pending but past 24 hours, the room closed, or
--                    the two are no longer friends; shown for 3 days after the
--                    invite was sent, then dropped)
--
-- ref_id is what an action takes: for a friend_request use actor_id with
-- accept/decline_friend_request; for a room_invite use ref_id (the invite id)
-- with accept/decline_room_invite; for a take_reply ref_id is the take.
create function private.inbox_items(p_me uuid)
returns table (
  item_key           text,
  kind               text,
  state              text,
  actor_id           uuid,
  actor_username     text,
  actor_display_name text,
  actor_avatar_url   text,
  ref_id             uuid,
  post_id            uuid,
  lobby_id           uuid,
  selected_game      text,
  member_count       integer,
  reply_count        integer,
  is_unread          boolean,
  sort_at            timestamptz,
  notification_id    uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select 'n:' || n.id, n.type, f.status,
         a.id, a.username, a.display_name, a.avatar_url,
         n.ref_id, null::uuid, null::uuid, null::text, null::integer,
         1, n.read_at is null, n.updated_at, n.id
    from public.notifications n
    join public.friendships f
      on f.id = n.ref_id and f.addressee_id = p_me and f.status in ('pending', 'accepted')
    join public.profiles a on a.id = n.actor_id and a.deleted_at is null
   where n.recipient_id = p_me and n.type = 'friend_request'

  union all

  select 'n:' || n.id, n.type, 'active',
         a.id, a.username, a.display_name, a.avatar_url,
         n.ref_id, c.post_id, null::uuid, null::text, null::integer,
         n.reply_count, n.read_at is null, n.updated_at, n.id
    from public.notifications n
    join public.prompt_comments c on c.id = n.ref_id and c.author_id = p_me
    join public.profiles a on a.id = n.actor_id and a.deleted_at is null
   where n.recipient_id = p_me and n.type = 'take_reply'
     and not private.blocked_either_way(p_me, n.actor_id)

  union all

  select 'i:' || i.id, 'room_invite',
         case when i.status <> 'pending' then i.status
              when i.created_at > now() - interval '24 hours'
                   and l.closed_at is null
                   and private.are_friends(p_me, i.sender_id) then 'pending'
              else 'expired' end,
         s.id, s.username, s.display_name, s.avatar_url,
         i.id, null::uuid, l.id, l.selected_game,
         (select count(*)::integer from public.lobby_members m
           where m.lobby_id = l.id and m.left_at is null),
         1,
         i.status = 'pending'
           and i.created_at > now() - interval '24 hours'
           and l.closed_at is null
           and private.are_friends(p_me, i.sender_id),
         i.created_at, null::uuid
    from public.room_invites i
    join public.lobbies l on l.id = i.lobby_id
    join public.profiles s on s.id = i.sender_id and s.deleted_at is null
   where i.recipient_id = p_me
     and i.created_at > now() - interval '3 days'
     and not private.blocked_either_way(p_me, i.sender_id);
$$;

revoke all on function private.blocked_either_way(uuid, uuid) from public, anon, authenticated;
revoke all on function private.notify_friend_request() from public, anon, authenticated;
revoke all on function private.notify_take_reply() from public, anon, authenticated;
revoke all on function private.inbox_items(uuid) from public, anon, authenticated;

-- -------------------------------------------------------------------- RPCs --

-- Newest activity first. Guests have no friends, takes or invites, so they get
-- an empty inbox rather than an error and the bell can render for everyone.
create function public.list_inbox(p_limit integer default 50)
returns table (
  item_key           text,
  kind               text,
  state              text,
  actor_id           uuid,
  actor_username     text,
  actor_display_name text,
  actor_avatar_url   text,
  ref_id             uuid,
  post_id            uuid,
  lobby_id           uuid,
  selected_game      text,
  member_count       integer,
  reply_count        integer,
  is_unread          boolean,
  sort_at            timestamptz
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
  return query
    select x.item_key, x.kind, x.state, x.actor_id, x.actor_username, x.actor_display_name,
           x.actor_avatar_url, x.ref_id, x.post_id, x.lobby_id, x.selected_game,
           x.member_count, x.reply_count, x.is_unread, x.sort_at
      from private.inbox_items(v_me) x
     order by x.sort_at desc, x.item_key
     limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

-- What the badge shows: unread stored items plus live pending invites, counted
-- through the same resolution as the list so the two never disagree.
create function public.inbox_unread_count()
returns integer
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
  return (select count(*)::integer from private.inbox_items(v_me) x where x.is_unread);
end;
$$;

-- Room invites are not marked read: they count as unread while pending and stop
-- when answered or expired. Returns whether a row changed.
create function public.mark_notification_read(p_item_key text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_item_key is null or p_item_key !~ '^n:[0-9a-f-]{36}$' then
    return false;
  end if;
  v_id := substr(p_item_key, 3)::uuid;
  update public.notifications set read_at = now()
   where id = v_id and recipient_id = v_me and read_at is null;
  return found;
end;
$$;

create function public.mark_all_notifications_read()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_n integer;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  update public.notifications set read_at = now()
   where recipient_id = v_me and read_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.list_inbox(integer) from public, anon;
revoke all on function public.inbox_unread_count() from public, anon;
revoke all on function public.mark_notification_read(text) from public, anon;
revoke all on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.list_inbox(integer) to authenticated;
grant execute on function public.inbox_unread_count() to authenticated;
grant execute on function public.mark_notification_read(text) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;

-- --------------------------------------------------------------- retention --

-- Read items go after 30 days. Anything untouched for 90 days goes whether or
-- not it was read, so rows for takes that nobody revisits don't pile up.
-- Orphans (source deleted) are already invisible; this only reclaims the rows.
create function private.prune_notifications()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.notifications
   where read_at < now() - interval '30 days'
      or updated_at < now() - interval '90 days';
$$;

revoke all on function private.prune_notifications() from public, anon, authenticated;

select cron.schedule('notifications-prune', '30 4 * * *', $$ select private.prune_notifications() $$);
