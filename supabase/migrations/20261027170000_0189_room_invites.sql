-- Room invites (Friends, BPP-3).
--
-- A member of an open room can invite a friend; the friend sees it in-app
-- (list_room_invites) and accepts or declines. Delivery is in-app only, no
-- push in v1. Accepting joins through the existing public.join_lobby, so
-- capacity, leaving other rooms and the account requirement stay in one place.
--
-- An invite is live while the room is open, within 24 hours, still pending,
-- and the sender and recipient are still friends. One row per (room,
-- recipient): inviting again after a decline or after the friend left
-- re-opens the same row. The table has RLS on and no grants; clients only
-- use the RPCs.

create table public.room_invites (
  id           uuid primary key default gen_random_uuid(),
  lobby_id     uuid not null references public.lobbies (id) on delete cascade,
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (sender_id <> recipient_id),
  unique (lobby_id, recipient_id)
);
create index room_invites_recipient_idx on public.room_invites (recipient_id, status);

alter table public.room_invites enable row level security;
revoke all on table public.room_invites from public, anon, authenticated;

-- Returns: invited | already_invited | already_in_room | room_full | unavailable
-- (not friends, or the room is gone/closed). Raises not_a_room_member (42501)
-- when the caller is not in the room, since that is a caller bug, not a probe.
create function public.invite_friend_to_room(p_lobby_id uuid, p_friend_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
  v_members integer;
begin
  perform private.rate_limit_hit('room_invite', 60, interval '1 hour');

  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and user_id = v_me and left_at is null
  ) then
    raise exception 'not_a_room_member' using errcode = '42501';
  end if;

  if p_friend_id is null
     or not exists (select 1 from public.lobbies where id = p_lobby_id and closed_at is null)
     or not private.are_friends(v_me, p_friend_id)
     or not exists (select 1 from public.profiles where id = p_friend_id and deleted_at is null) then
    return 'unavailable';
  end if;

  if exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and user_id = p_friend_id and left_at is null
  ) then
    return 'already_in_room';
  end if;

  select count(*) into v_members from public.lobby_members
   where lobby_id = p_lobby_id and left_at is null;
  if v_members >= 4 then
    return 'room_full';
  end if;

  if exists (
    select 1 from public.room_invites
     where lobby_id = p_lobby_id and recipient_id = p_friend_id
       and status = 'pending' and created_at > now() - interval '24 hours'
  ) then
    return 'already_invited';
  end if;

  insert into public.room_invites (lobby_id, sender_id, recipient_id)
  values (p_lobby_id, v_me, p_friend_id)
  on conflict (lobby_id, recipient_id) do update
    set sender_id = excluded.sender_id, status = 'pending',
        created_at = now(), responded_at = null;
  return 'invited';
end;
$$;

-- The caller's live invites, newest first.
create function public.list_room_invites()
returns table (
  invite_id uuid,
  lobby_id uuid,
  sender_id uuid,
  sender_username text,
  sender_display_name text,
  sender_avatar_url text,
  selected_game text,
  member_count integer,
  created_at timestamptz
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
    select i.id, i.lobby_id, i.sender_id, s.username, s.display_name, s.avatar_url,
           l.selected_game,
           (select count(*)::integer from public.lobby_members m where m.lobby_id = l.id and m.left_at is null),
           i.created_at
      from public.room_invites i
      join public.lobbies l on l.id = i.lobby_id and l.closed_at is null
      join public.profiles s on s.id = i.sender_id and s.deleted_at is null
     where i.recipient_id = v_me
       and i.status = 'pending'
       and i.created_at > now() - interval '24 hours'
       and private.are_friends(v_me, i.sender_id)
     order by i.created_at desc, i.id;
end;
$$;

-- Joins the room through join_lobby and returns it (same shape as join_lobby).
-- Errors: invite_not_found (P0001) for anything not live, plus join_lobby's own
-- lobby_full / account_required.
create function public.accept_room_invite(p_invite_id uuid)
returns public.lobbies
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
  v_invite public.room_invites;
  v_code text;
  v_lobby public.lobbies;
begin
  select i.* into v_invite
    from public.room_invites i
    join public.lobbies l on l.id = i.lobby_id and l.closed_at is null
   where i.id = p_invite_id and i.recipient_id = v_me and i.status = 'pending'
     and i.created_at > now() - interval '24 hours'
     and private.are_friends(v_me, i.sender_id);
  if not found then
    raise exception 'invite_not_found' using errcode = 'P0001';
  end if;

  select code into v_code from public.lobbies where id = v_invite.lobby_id;
  v_lobby := public.join_lobby(v_code);

  update public.room_invites set status = 'accepted', responded_at = now() where id = v_invite.id;
  return v_lobby;
end;
$$;

create function public.decline_room_invite(p_invite_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  update public.room_invites
     set status = 'declined', responded_at = now()
   where id = p_invite_id and recipient_id = v_me and status = 'pending';
  return found;
end;
$$;

revoke all on function public.invite_friend_to_room(uuid, uuid) from public, anon;
revoke all on function public.list_room_invites() from public, anon;
revoke all on function public.accept_room_invite(uuid) from public, anon;
revoke all on function public.decline_room_invite(uuid) from public, anon;
grant execute on function public.invite_friend_to_room(uuid, uuid) to authenticated;
grant execute on function public.list_room_invites() to authenticated;
grant execute on function public.accept_room_invite(uuid) to authenticated;
grant execute on function public.decline_room_invite(uuid) to authenticated;
