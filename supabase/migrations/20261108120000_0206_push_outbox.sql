-- APNs sending (GitHub #172, part 4 of 4).
--
-- Four events become pushes: a new prompt, a friend request, a room invite and
-- a reply to your take. The inbox (0204) stays the source of truth and a push is
-- only an alert about it, so this migration never changes what the inbox shows.
--
-- Pushes go through an outbox written in the same transaction as the event.
-- A separate sender (the send-push Edge Function) claims rows, talks to APNs and
-- reports back, so APNs being slow or down can never delay or fail the action
-- that caused the push. Every enqueue is wrapped so that even a bug here cannot
-- fail the triggering insert.
--
--   Coalescing   an unclaimed row per (recipient, kind, ref) is unique, so
--                several replies to one take inside the delay window are one push.
--   Suppression  decided when the row is claimed, not only when it is written:
--                a block, a deleted account, an item already read or answered,
--                an invite that expired or a prompt that has locked all drop the push.
--   Delivery     claim_push_batch hands the sender each push with the
--                recipient's devices and badge; finish_push records the outcome.
--
-- The table has RLS on and no grants. The two sender RPCs are service_role only.

create table public.push_outbox (
  id           bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  kind         text not null check (kind in ('friend_request', 'take_reply', 'room_invite', 'new_prompt')),
  -- friend_request / take_reply: the notifications row. room_invite: the invite.
  -- new_prompt: the post.
  ref_id       uuid not null,
  -- The inbox item this is an alert for ('n:<id>' or 'i:<id>'); null for new_prompt.
  item_key     text,
  actor_id     uuid references public.profiles (id) on delete cascade,
  post_id      uuid references public.prompt_posts (id) on delete cascade,
  created_at   timestamptz not null default now(),
  -- Not sent before this. Replies wait a little so a burst becomes one push.
  available_at timestamptz not null default now(),
  claimed_at   timestamptz,
  attempts     integer not null default 0,
  sent_at      timestamptz,
  dead_at      timestamptz,
  last_error   text
);

create unique index push_outbox_pending_idx
  on public.push_outbox (recipient_id, kind, ref_id)
  where claimed_at is null and sent_at is null and dead_at is null;
create index push_outbox_due_idx on public.push_outbox (available_at)
  where sent_at is null and dead_at is null;

alter table public.push_outbox enable row level security;
revoke all on table public.push_outbox from public, anon, authenticated;

-- ---------------------------------------------------------------- enqueue --

-- Never raises: a push is best-effort and must not fail the action behind it.
create function private.enqueue_push(
  p_recipient uuid,
  p_kind      text,
  p_ref_id    uuid,
  p_item_key  text,
  p_actor     uuid,
  p_delay     interval default interval '0'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Nobody to alert unless a device is registered.
  if not exists (select 1 from public.device_tokens where user_id = p_recipient) then
    return;
  end if;
  insert into public.push_outbox (recipient_id, kind, ref_id, item_key, actor_id, available_at)
  values (p_recipient, p_kind, p_ref_id, p_item_key, p_actor, now() + p_delay)
  on conflict (recipient_id, kind, ref_id)
    where claimed_at is null and sent_at is null and dead_at is null
  do nothing;
exception when others then
  raise warning 'enqueue_push failed: %', sqlerrm;
end;
$$;

-- Broadcast to every user with a device, except the admin who made the post.
create function private.enqueue_new_prompt_push(p_post_id uuid, p_author uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.push_outbox (recipient_id, kind, ref_id, post_id)
  select distinct t.user_id, 'new_prompt', p_post_id, p_post_id
    from public.device_tokens t
    join public.profiles p on p.id = t.user_id and p.deleted_at is null
   where t.user_id <> p_author
  on conflict (recipient_id, kind, ref_id)
    where claimed_at is null and sent_at is null and dead_at is null
  do nothing;
exception when others then
  raise warning 'enqueue_new_prompt_push failed: %', sqlerrm;
end;
$$;

create function private.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A new item, a further reply, or a reply on an item the owner had read (0204
  -- resets read_at) is worth an alert. Marking read only sets read_at, so it never
  -- lands here.
  if new.read_at is null and (tg_op = 'INSERT' or old.read_at is not null or new.reply_count > old.reply_count) then
    perform private.enqueue_push(
      new.recipient_id, new.type, new.id, 'n:' || new.id, new.actor_id,
      case when new.type = 'take_reply' then interval '30 seconds' else interval '0' end
    );
  end if;
  return new;
end;
$$;

create trigger notifications_push
  after insert or update on public.notifications
  for each row execute function private.push_on_notification();

create function private.push_on_room_invite()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'pending'
     and (tg_op = 'INSERT' or old.status is distinct from 'pending' or new.created_at is distinct from old.created_at) then
    perform private.enqueue_push(new.recipient_id, 'room_invite', new.id, 'i:' || new.id, new.sender_id);
  end if;
  return new;
end;
$$;

create trigger room_invites_push
  after insert or update on public.room_invites
  for each row execute function private.push_on_room_invite();

-- create_post gains p_send_push (the admin form's "don't notify" checkbox). A new
-- argument means a new function, so the old signature goes and the grants are
-- repeated. Existing ten-argument calls resolve to this one through the default.
-- Same body as 0175's otherwise.
drop function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb, boolean, text[]);

create function prompts.create_post(
  p_template_kind       text,
  p_template_name       text,
  p_caption             text,
  p_prompt_text         text,
  p_resolution_criteria text,
  p_lock_at             timestamptz,
  p_slots               jsonb,
  p_resolution_source   jsonb default null,
  p_is_opinion          boolean default false,
  p_cover_team_codes    text[] default null,
  p_send_push           boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user         uuid := auth.uid();
  v_post_id      uuid;
  v_slot         jsonb;
  v_option       jsonb;
  v_slot_id      uuid;
  v_slot_ids     uuid[] := '{}';
  v_idx          int := 0;
  v_option_count int;
  v_team_count   int;
  v_missing_code int;
  v_positions    int[];
  v_pos          int;
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- Keep the cross-week comparison meaningful: every Power Rankings post is
  -- exactly one, full-league team slot, and it can never be graded.
  if p_template_kind = 'power_rankings' then
    select count(*), count(distinct option ->> 'team_code'), count(*) filter (where coalesce(option ->> 'team_code', '') = '')
      into v_option_count, v_team_count, v_missing_code
      from jsonb_array_elements(coalesce(p_slots -> 0 -> 'options', '[]'::jsonb)) option;
    if not p_is_opinion
       or p_resolution_source is not null
       or jsonb_array_length(p_slots) <> 1
       or p_slots -> 0 ->> 'shape' <> 'rank'
       or coalesce((p_slots -> 0 ->> 'pick_count')::int, 0) <> 32
       or v_option_count <> 32
       or v_team_count <> 32
       or v_missing_code <> 0 then
      raise exception 'invalid_power_rankings' using errcode = '22023';
    end if;

    -- The cover is six distinct teams from this post's own pool.
    if cardinality(p_cover_team_codes) is distinct from 6
       or (select count(distinct code) from unnest(p_cover_team_codes) code) <> 6
       or exists (
         select 1 from unnest(p_cover_team_codes) code
         where not exists (
           select 1 from jsonb_array_elements(p_slots -> 0 -> 'options') option where option ->> 'team_code' = code
         )
       ) then
      raise exception 'invalid_cover_teams' using errcode = '22023';
    end if;
  elsif p_cover_team_codes is not null then
    raise exception 'invalid_cover_teams' using errcode = '22023';
  end if;

  -- Weekly Awards: opinion only, six `pick` slots. Slots 1-2 offer all 32 teams,
  -- slot 3 at least one matchup, slots 4-6 are player searches with no options.
  if p_template_kind = 'weekly_awards' then
    for v_pos in 0..5 loop
      v_slot := p_slots -> v_pos;
      select count(*), count(distinct option ->> 'team_code')
        into v_option_count, v_team_count
        from jsonb_array_elements(coalesce(v_slot -> 'options', '[]'::jsonb)) option;
      if not p_is_opinion
         or p_resolution_source is not null
         or jsonb_array_length(p_slots) <> 6
         or v_slot ->> 'shape' <> 'pick'
         or (v_pos < 2 and (coalesce((v_slot ->> 'player_search')::boolean, false) or v_option_count <> 32 or v_team_count <> 32))
         or (v_pos = 2 and (coalesce((v_slot ->> 'player_search')::boolean, false) or v_option_count < 1))
         or (v_pos > 2 and (not coalesce((v_slot ->> 'player_search')::boolean, false) or v_option_count <> 0)) then
        raise exception 'invalid_weekly_awards' using errcode = '22023';
      end if;
    end loop;
  elsif exists (
    select 1 from jsonb_array_elements(p_slots) s where coalesce((s ->> 'player_search')::boolean, false)
  ) then
    raise exception 'invalid_weekly_awards' using errcode = '22023';
  end if;

  -- The art positions on a slot's options: 1..k, at most four, stat_leader only.
  for v_slot in select jsonb_array_elements(p_slots) loop
    select coalesce(array_agg((option ->> 'cover_position')::int order by (option ->> 'cover_position')::int), '{}')
      into v_positions
      from jsonb_array_elements(coalesce(v_slot -> 'options', '[]'::jsonb)) option
      where option ->> 'cover_position' is not null;
    if cardinality(v_positions) > 0
       and (p_template_kind <> 'stat_leader'
            or cardinality(v_positions) > 4
            or v_positions <> array(select generate_series(1, cardinality(v_positions)))) then
      raise exception 'invalid_cover_options' using errcode = '22023';
    end if;
  end loop;

  insert into public.prompt_posts
    (template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, resolution_source, is_opinion, cover_team_codes)
  values
    (p_template_kind, p_template_name, v_user, p_caption, p_prompt_text, p_resolution_criteria, p_lock_at, p_resolution_source, p_is_opinion, p_cover_team_codes)
  returning id into v_post_id;

  for v_slot in select jsonb_array_elements(p_slots) loop
    insert into public.prompt_slots (post_id, label, shape, pick_count, points, sort_order, source_game_id, player_search)
    values (
      v_post_id,
      v_slot ->> 'label',
      v_slot ->> 'shape',
      coalesce((v_slot ->> 'pick_count')::smallint, case when v_slot ->> 'shape' = 'rank' then jsonb_array_length(coalesce(v_slot -> 'options', '[]'::jsonb))::smallint end),
      (v_slot ->> 'points')::smallint,
      v_idx,
      v_slot ->> 'source_game_id',
      coalesce((v_slot ->> 'player_search')::boolean, false)
    ) returning id into v_slot_id;
    v_slot_ids := v_slot_ids || v_slot_id;

    for v_option in select jsonb_array_elements(coalesce(v_slot -> 'options', '[]'::jsonb)) loop
      insert into public.prompt_slot_options (slot_id, label, sublabel, team_code, headshot_url, sort_order, cover_position, margin)
      values (
        v_slot_id,
        v_option ->> 'label',
        v_option ->> 'sublabel',
        v_option ->> 'team_code',
        v_option ->> 'headshot_url',
        coalesce((v_option ->> 'sort_order')::smallint, 0),
        (v_option ->> 'cover_position')::smallint,
        v_option ->> 'margin'
      );
    end loop;
    v_idx := v_idx + 1;
  end loop;

  v_idx := 0;
  for v_slot in select jsonb_array_elements(p_slots) loop
    insert into public.prompt_slot_exclusions (slot_id, excluded_slot_id)
    select v_slot_ids[v_idx + 1], v_slot_ids[(elem)::int + 1]
    from jsonb_array_elements_text(coalesce(v_slot -> 'excludes_slot_indexes', '[]'::jsonb)) elem;
    v_idx := v_idx + 1;
  end loop;
  if p_send_push then
    perform private.enqueue_new_prompt_push(v_post_id, v_user);
  end if;
  return v_post_id;
end;
$$;

revoke all on function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb, boolean, text[], boolean) from public, anon;
grant execute on function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb, boolean, text[], boolean) to authenticated;

revoke all on function private.enqueue_push(uuid, text, uuid, text, uuid, interval) from public, anon, authenticated;
revoke all on function private.enqueue_new_prompt_push(uuid, uuid) from public, anon, authenticated;
revoke all on function private.push_on_notification() from public, anon, authenticated;
revoke all on function private.push_on_room_invite() from public, anon, authenticated;

-- ------------------------------------------------------------------ sender --

-- Why a queued push should not go out any more, or null. Checked at claim time
-- because the world moves between the event and the send.
create function private.push_suppression(p_row public.push_outbox)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = p_row.recipient_id and deleted_at is null) then
    return 'recipient_gone';
  end if;
  if p_row.kind = 'new_prompt' then
    if not exists (
      select 1 from public.prompt_posts where id = p_row.post_id and status = 'open' and lock_at > now()
    ) then
      return 'prompt_closed';
    end if;
    return null;
  end if;
  if p_row.actor_id is not null and private.blocked_either_way(p_row.recipient_id, p_row.actor_id) then
    return 'blocked';
  end if;
  -- The inbox is the truth: gone, read, answered or expired means nothing to alert about.
  if not exists (
    select 1 from private.inbox_items(p_row.recipient_id) x
     where x.item_key = p_row.item_key and x.is_unread
  ) then
    return 'not_unread';
  end if;
  return null;
end;
$$;

-- Hands the sender up to p_limit due pushes, each with the recipient's devices
-- and badge (their unread inbox count). A claim lasts two minutes; a sender that
-- dies mid-batch just lets the rows come due again. Rows older than an hour are
-- dropped: an alert that late is noise.
create function public.claim_push_batch(p_limit integer default 50)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_row    public.push_outbox;
  v_why    text;
  v_result jsonb := '[]'::jsonb;
  v_devices jsonb;
begin
  update public.push_outbox
     set dead_at = now(), last_error = 'expired'
   where sent_at is null and dead_at is null
     and created_at < now() - interval '1 hour'
     and (claimed_at is null or claimed_at < now() - interval '2 minutes');

  for v_row in
    select * from public.push_outbox
     where sent_at is null and dead_at is null
       and available_at <= now()
       and (claimed_at is null or claimed_at < now() - interval '2 minutes')
     order by id
     limit greatest(1, least(coalesce(p_limit, 50), 200))
     for update skip locked
  loop
    v_why := private.push_suppression(v_row);
    if v_why is not null then
      update public.push_outbox set dead_at = now(), last_error = 'suppressed: ' || v_why where id = v_row.id;
      continue;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment)), '[]'::jsonb)
      into v_devices
      from public.device_tokens t where t.user_id = v_row.recipient_id;
    if jsonb_array_length(v_devices) = 0 then
      update public.push_outbox set dead_at = now(), last_error = 'no_devices' where id = v_row.id;
      continue;
    end if;

    update public.push_outbox set claimed_at = now(), attempts = attempts + 1 where id = v_row.id;
    v_result := v_result || jsonb_build_object(
      'id', v_row.id,
      'kind', v_row.kind,
      'item_key', v_row.item_key,
      'post_id', v_row.post_id,
      'badge', (select count(*)::integer from private.inbox_items(v_row.recipient_id) x where x.is_unread),
      'devices', v_devices
    );
  end loop;
  return v_result;
end;
$$;

-- p_result: sent | retry | dead. A retry waits longer each time and gives up after five.
create function public.finish_push(p_id bigint, p_result text, p_error text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_result = 'sent' then
    update public.push_outbox set sent_at = now(), last_error = null where id = p_id;
  elsif p_result = 'retry' then
    update public.push_outbox
       set claimed_at = null,
           available_at = now() + least(attempts, 5) * interval '30 seconds',
           last_error = p_error,
           dead_at = case when attempts >= 5 then now() end
     where id = p_id;
  else
    update public.push_outbox set dead_at = now(), last_error = p_error where id = p_id;
  end if;
end;
$$;

revoke all on function private.push_suppression(public.push_outbox) from public, anon, authenticated;
revoke all on function public.claim_push_batch(integer) from public, anon, authenticated;
revoke all on function public.finish_push(bigint, text, text) from public, anon, authenticated;
grant execute on function public.claim_push_batch(integer) to service_role;
grant execute on function public.finish_push(bigint, text, text) to service_role;

-- ------------------------------------------------------------------- drain --

-- Wakes the send-push Edge Function every 15 seconds. The function URL and its
-- shared secret live in Vault ('push_function_url', 'push_function_secret'); until
-- they are set, as on a local stack with no APNs, this does nothing and the outbox
-- simply ages out. net.http_post only queues the request, so a slow or failing
-- function never holds this up.
create function private.push_drain_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_function_secret';
  if v_url is null or v_secret is null then
    return;
  end if;
  if not exists (
    select 1 from public.push_outbox
     where sent_at is null and dead_at is null and available_at <= now()
  ) then
    return;
  end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
exception when others then
  raise warning 'push_drain_tick failed: %', sqlerrm;
end;
$$;

create function private.prune_push_outbox()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_outbox where created_at < now() - interval '7 days';
$$;

revoke all on function private.push_drain_tick() from public, anon, authenticated;
revoke all on function private.prune_push_outbox() from public, anon, authenticated;

create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('push-drain', '15 seconds', $$ select private.push_drain_tick() $$);
select cron.schedule('push-outbox-prune', '30 4 * * *', $$ select private.prune_push_outbox() $$);
