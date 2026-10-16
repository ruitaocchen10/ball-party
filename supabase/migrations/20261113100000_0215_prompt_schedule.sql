-- BPP-15: the admin prompt calendar.
--
-- A planning table, kept apart from public.prompt_posts on purpose. Many
-- security-definer readers (feeds, leaderboards, notifications) assume every
-- prompt_posts row is a real prompt, so a draft or "ready" row there could leak
-- to players through any reader that forgot a status filter. Here a draft is a
-- row nothing player-facing reads. When a ready slot's opens_at arrives, a
-- one-minute tick runs the existing prompts.create_post with the stored
-- arguments and records the new post on the slot.
--
-- Slots are made ahead of time with the time they should be posted (opens_at)
-- already set, from a fixed weekly cadence (see schedule_prefill).
--
-- Slot states (stored): empty -> draft -> ready -> published. The calendar also
-- shows live / locked / resolved, derived from the linked post.
--
-- Everything is admin-only (prompts_private.is_admin()) and reached through
-- prompts.* RPCs. Times are timestamptz; the UI and digest display US Eastern.

create table prompts_private.schedule_slots (
  id            uuid primary key default gen_random_uuid(),
  season        smallint not null,
  -- NFL week, the same numbering as public.nfl_games.week.
  week          smallint not null,
  kind          text not null check (kind in ('game_pick', 'weekly_picks', 'weekly_awards', 'bold_predictions', 'power_rankings')),
  -- Set for game_pick only: the nflverse game this slot is for.
  game_id       text,
  state         text not null default 'empty' check (state in ('empty', 'draft', 'ready', 'published')),
  -- { "post": <prompts.create_post arguments, keyed by parameter name>, "composer": <opaque editor state> }
  payload       jsonb,
  opens_at      timestamptz,
  lock_at       timestamptz,
  author_id     uuid references public.profiles (id) on delete set null,
  post_id       uuid references public.prompt_posts (id) on delete set null,
  -- Why the last attempt to open this slot failed; cleared on success or edit.
  publish_error text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check ((kind = 'game_pick') = (game_id is not null)),
  check ((state = 'empty') = (payload is null))
);

-- One slot per (week, kind, game): re-running the pre-fill adds nothing.
create unique index schedule_slots_unique
  on prompts_private.schedule_slots (season, week, kind, coalesce(game_id, ''));
create index schedule_slots_ready_opens
  on prompts_private.schedule_slots (opens_at) where state = 'ready';

revoke all on table prompts_private.schedule_slots from public, anon, authenticated;
alter table prompts_private.schedule_slots enable row level security;

-- ------------------------------------------------------------------ rules --

-- The manual steps still missing before a slot can be marked ready, in plain
-- words. Empty when the slot is complete.
create function prompts_private.schedule_missing(
  p_kind text, p_game_id text, p_payload jsonb, p_opens_at timestamptz, p_lock_at timestamptz
)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_missing text[] := '{}';
  v_post    jsonb := p_payload -> 'post';
begin
  if p_payload is null then
    v_missing := v_missing || 'No prompt written'::text;
  elsif v_post ->> 'p_template_kind' is distinct from p_kind then
    v_missing := v_missing || 'Prompt is not this kind'::text;
  else
    if btrim(coalesce(v_post ->> 'p_caption', '')) = '' then
      v_missing := v_missing || 'No caption'::text;
    end if;
    if btrim(coalesce(v_post ->> 'p_resolution_criteria', '')) = '' then
      v_missing := v_missing || 'No resolution criteria'::text;
    end if;
    if p_kind = 'game_pick' and not exists (
      select 1 from jsonb_array_elements(coalesce(v_post -> 'p_slots', '[]'::jsonb)) s
       where s ->> 'source_game_id' = p_game_id
    ) then
      v_missing := v_missing || 'No game picked'::text;
    end if;
  end if;
  if p_opens_at is null then
    v_missing := v_missing || 'No open time'::text;
  end if;
  if p_lock_at is null then
    v_missing := v_missing || 'No lock time'::text;
  elsif p_opens_at is not null and p_opens_at >= p_lock_at then
    v_missing := v_missing || 'Opens after it locks'::text;
  end if;
  return v_missing;
end;
$$;

-- Runs the payload through the real create_post and rolls it back, so "mark
-- ready" catches everything create_post would reject. Returns the error text,
-- or null when it would have been created. Must run as the admin (auth.uid()).
create function prompts_private.schedule_dry_run(p_payload jsonb, p_lock_at timestamptz)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post jsonb := p_payload -> 'post';
begin
  begin
    perform prompts.create_post(
      v_post ->> 'p_template_kind',
      v_post ->> 'p_template_name',
      v_post ->> 'p_caption',
      v_post ->> 'p_prompt_text',
      v_post ->> 'p_resolution_criteria',
      p_lock_at,
      v_post -> 'p_slots',
      v_post -> 'p_resolution_source',
      coalesce((v_post ->> 'p_is_opinion')::boolean, false),
      case when jsonb_typeof(v_post -> 'p_cover_team_codes') = 'array'
           then array(select jsonb_array_elements_text(v_post -> 'p_cover_team_codes')) end,
      false
    );
    raise exception 'schedule_dry_run_ok' using errcode = 'P0DRY';
  exception
    when sqlstate 'P0DRY' then
      return null;
    when others then
      return sqlerrm;
  end;
end;
$$;

-- ------------------------------------------------------------------ view --

-- One row per slot with everything the calendar, queue and digest need.
-- due_at is when the slot has to be ready by: its open time, or its lock time
-- while no open time is set. A slot "needs attention" when it is still empty or
-- a draft, can still be played (lock_at ahead), and is due within 2 days; or
-- when its last attempt to open failed.
create view prompts_private.schedule_slot_view as
select
  s.id, s.season, s.week, s.kind, s.game_id, s.state,
  case
    when s.state <> 'published' then s.state
    when p.id is null then 'removed'
    when p.status = 'open' then 'live'
    else p.status
  end as display_state,
  s.opens_at, s.lock_at, s.post_id, s.publish_error,
  s.payload is not null as has_draft,
  s.payload -> 'post' ->> 'p_caption' as caption,
  m.missing,
  coalesce(s.opens_at, s.lock_at) as due_at,
  (
    s.publish_error is not null
    or (
      s.state in ('empty', 'draft')
      and s.lock_at > now()
      and coalesce(s.opens_at, s.lock_at) <= now() + interval '2 days'
    )
  ) as needs_attention,
  case
    when s.publish_error is not null then 'Failed to open: ' || s.publish_error
    when s.state in ('empty', 'draft') then array_to_string(m.missing, '; ')
  end as attention
from prompts_private.schedule_slots s
left join public.prompt_posts p on p.id = s.post_id
cross join lateral (
  select prompts_private.schedule_missing(s.kind, s.game_id, s.payload, s.opens_at, s.lock_at) as missing
) m;

revoke all on prompts_private.schedule_slot_view from public, anon, authenticated;

-- --------------------------------------------------------------- pre-fill --

-- Noon US Eastern on a calendar date (12:00 on the clock in New York, whichever
-- of EST and EDT is in force that day).
create function prompts_private.et_noon(p_date date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select (p_date + time '12:00') at time zone 'America/New_York';
$$;

-- The date of weekday p_dow (0 = Sunday .. 6 = Saturday) strictly before, or
-- strictly after, p_date: always 1 to 7 days away.
create function prompts_private.weekday_before(p_date date, p_dow integer)
returns date
language sql
immutable
set search_path = ''
as $$
  select p_date - (((extract(dow from p_date)::integer - p_dow + 6) % 7) + 1);
$$;

create function prompts_private.weekday_after(p_date date, p_dow integer)
returns date
language sql
immutable
set search_path = ''
as $$
  select p_date + (((p_dow - extract(dow from p_date)::integer + 6) % 7) + 1);
$$;

-- Creates the empty slots, each already carrying the time it should be posted
-- (opens_at) and the time it should lock, so the calendar can put it on its
-- day. Idempotent: the unique index means re-running adds nothing. Returns how
-- many slots it added. A slot is made while it can still be played (its lock is
-- ahead) and opens within the horizon.
--
-- The cadence, for an NFL week whose games run Thursday to Monday (all times
-- US Eastern):
--   game_pick         primetime games only; opens noon on game day, locks at kickoff
--   weekly_picks      opens noon the Wednesday before the week's first kickoff, locks at it
--   weekly_awards     about this week's games; opens noon the Tuesday after the
--                     week's last game, locks noon the next day
--   power_rankings    the "pre-week" preview; opens noon the Tuesday before the
--                     week's first kickoff, locks noon the next day
--   bold_predictions  opens noon the day before the week's first Sunday kickoff,
--                     locks at that kickoff (a week with no Sunday game gets none)
create function prompts_private.schedule_prefill(p_horizon interval default interval '21 days')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_added integer;
begin
  with weeks as (
    select season, week,
           min(kickoff) as first_kick,
           (min(kickoff) at time zone 'America/New_York')::date as first_day,
           (max(kickoff) at time zone 'America/New_York')::date as last_day,
           min(kickoff) filter (where extract(dow from kickoff at time zone 'America/New_York') = 0) as sunday_kick
      from public.nfl_games
     group by season, week
  ), planned as (
    select g.season, g.week, 'game_pick'::text as kind, g.id as game_id,
           prompts_private.et_noon((g.kickoff at time zone 'America/New_York')::date) as opens_at,
           g.kickoff as lock_at
      from public.nfl_games g
     where g.primetime
    union all
    select season, week, 'weekly_picks', null::text,
           prompts_private.et_noon(prompts_private.weekday_before(first_day, 3)), first_kick
      from weeks
    union all
    select season, week, 'weekly_awards', null::text,
           prompts_private.et_noon(prompts_private.weekday_after(last_day, 2)),
           prompts_private.et_noon(prompts_private.weekday_after(last_day, 2) + 1)
      from weeks
    union all
    select season, week, 'power_rankings', null::text,
           prompts_private.et_noon(prompts_private.weekday_before(first_day, 2)),
           prompts_private.et_noon(prompts_private.weekday_before(first_day, 2) + 1)
      from weeks
    union all
    select season, week, 'bold_predictions', null::text,
           prompts_private.et_noon((sunday_kick at time zone 'America/New_York')::date - 1), sunday_kick
      from weeks
     where sunday_kick is not null
  ), inserted as (
    insert into prompts_private.schedule_slots (season, week, kind, game_id, opens_at, lock_at)
    select season, week, kind, game_id, opens_at, lock_at
      from planned
     where lock_at > now() and opens_at <= now() + p_horizon
    on conflict do nothing
    returning 1
  )
  select count(*) into v_added from inserted;
  return v_added;
end;
$$;

revoke all on function prompts_private.et_noon(date) from public, anon, authenticated;
revoke all on function prompts_private.weekday_before(date, integer) from public, anon, authenticated;
revoke all on function prompts_private.weekday_after(date, integer) from public, anon, authenticated;
revoke all on function prompts_private.schedule_prefill(interval) from public, anon, authenticated;

-- -------------------------------------------------------------- admin RPCs --

create function prompts_private.schedule_require_admin()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
end;
$$;

revoke all on function prompts_private.schedule_require_admin() from public, anon, authenticated;

-- Adds missing slots for the coming weeks (also run daily by cron).
create function prompts.schedule_prefill()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform prompts_private.schedule_require_admin();
  return prompts_private.schedule_prefill();
end;
$$;

-- The calendar's days: every slot whose day falls in [p_from, p_to). A slot sits
-- on the day it opens, or on its due day (its lock time) until it has an open time.
create function prompts.schedule_range(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform prompts_private.schedule_require_admin();
  return coalesce((
    select jsonb_agg(to_jsonb(v) order by v.due_at, v.kind, v.game_id)
      from prompts_private.schedule_slot_view v
     where v.due_at >= p_from and v.due_at < p_to
  ), '[]'::jsonb);
end;
$$;

-- Drafts, ready slots, and anything that failed to open: the queue.
create function prompts.schedule_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform prompts_private.schedule_require_admin();
  return coalesce((
    select jsonb_agg(to_jsonb(v) order by v.due_at nulls last, v.kind)
      from prompts_private.schedule_slot_view v
     where v.state in ('draft', 'ready')
  ), '[]'::jsonb);
end;
$$;

-- One slot with its draft, for opening the composer.
create function prompts.schedule_get(p_slot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  perform prompts_private.schedule_require_admin();
  select to_jsonb(v) || jsonb_build_object('payload', s.payload)
    into v_row
    from prompts_private.schedule_slot_view v
    join prompts_private.schedule_slots s on s.id = v.id
   where v.id = p_slot;
  if v_row is null then
    raise exception 'slot_not_found' using errcode = 'P0002';
  end if;
  return v_row;
end;
$$;

-- Saves the composer's work as a draft. A ready slot drops back to draft:
-- changing it means re-checking it. A published slot is read-only.
create function prompts.schedule_save_draft(
  p_slot uuid, p_payload jsonb, p_opens_at timestamptz, p_lock_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform prompts_private.schedule_require_admin();
  if p_payload is null or jsonb_typeof(p_payload -> 'post') is distinct from 'object' then
    raise exception 'invalid_payload' using errcode = '22023';
  end if;
  update prompts_private.schedule_slots
     set state = 'draft', payload = p_payload, opens_at = p_opens_at, lock_at = p_lock_at,
         publish_error = null, updated_at = now()
   where id = p_slot and state <> 'published';
  if not found then
    raise exception 'slot_not_editable' using errcode = 'P0002';
  end if;
end;
$$;

-- Queues a complete draft to open at its opens_at. Fails, naming each missing
-- step, if anything is incomplete or create_post would reject it.
create function prompts.schedule_mark_ready(p_slot uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slot    prompts_private.schedule_slots;
  v_missing text[];
  v_error   text;
begin
  perform prompts_private.schedule_require_admin();
  select * into v_slot from prompts_private.schedule_slots where id = p_slot for update;
  if not found or v_slot.state not in ('draft', 'ready') then
    raise exception 'slot_not_editable' using errcode = 'P0002';
  end if;

  v_missing := prompts_private.schedule_missing(v_slot.kind, v_slot.game_id, v_slot.payload, v_slot.opens_at, v_slot.lock_at);
  if cardinality(v_missing) > 0 then
    raise exception 'not_ready: %', array_to_string(v_missing, '; ') using errcode = '22023';
  end if;
  if v_slot.lock_at <= now() then
    raise exception 'not_ready: Lock time has passed' using errcode = '22023';
  end if;

  v_error := prompts_private.schedule_dry_run(v_slot.payload, v_slot.lock_at);
  if v_error is not null then
    raise exception 'not_ready: %', v_error using errcode = '22023';
  end if;

  update prompts_private.schedule_slots
     set state = 'ready', author_id = auth.uid(), publish_error = null, updated_at = now()
   where id = p_slot;
end;
$$;

-- Takes a ready slot back out of the queue so it can be edited.
create function prompts.schedule_unready(p_slot uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform prompts_private.schedule_require_admin();
  update prompts_private.schedule_slots
     set state = 'draft', updated_at = now()
   where id = p_slot and state = 'ready';
  if not found then
    raise exception 'slot_not_editable' using errcode = 'P0002';
  end if;
end;
$$;

-- Throws a draft away, leaving the slot empty.
create function prompts.schedule_clear(p_slot uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform prompts_private.schedule_require_admin();
  update prompts_private.schedule_slots
     set state = 'empty', payload = null, opens_at = null, author_id = null,
         publish_error = null, updated_at = now()
   where id = p_slot and state in ('draft', 'ready');
  if not found then
    raise exception 'slot_not_editable' using errcode = 'P0002';
  end if;
end;
$$;

-- Records that a prompt published straight from Compose covers the slot with
-- this key, so the calendar stops asking for it. Nothing to do (and no error)
-- when there is no such slot or it is already taken.
create function prompts.schedule_link_post(p_post uuid, p_kind text, p_season smallint, p_week smallint, p_game_id text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform prompts_private.schedule_require_admin();
  update prompts_private.schedule_slots
     set state = 'published', post_id = p_post, author_id = auth.uid(), updated_at = now(),
         payload = coalesce(payload, '{"post": {}}'::jsonb), publish_error = null
   where season = p_season and week = p_week and kind = p_kind
     and game_id is not distinct from p_game_id
     and state <> 'published';
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'prompts.schedule_prefill()',
    'prompts.schedule_range(timestamptz, timestamptz)', 'prompts.schedule_queue()',
    'prompts.schedule_get(uuid)', 'prompts.schedule_save_draft(uuid, jsonb, timestamptz, timestamptz)',
    'prompts.schedule_mark_ready(uuid)', 'prompts.schedule_unready(uuid)',
    'prompts.schedule_clear(uuid)', 'prompts.schedule_link_post(uuid, text, smallint, smallint, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke all on function prompts_private.schedule_missing(text, text, jsonb, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function prompts_private.schedule_dry_run(jsonb, timestamptz) from public, anon, authenticated;

-- ------------------------------------------------------------------- tick --

-- Opens every ready slot whose time has come. Each slot runs in its own
-- subtransaction as the admin who marked it ready (create_post checks the
-- caller's JWT email against the admin list, so the claims are set for the
-- duration). A slot that fails goes back to draft with the reason, so it is
-- flagged on the calendar and not retried every minute.
create function prompts_private.promote_scheduled_tick()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slot     prompts_private.schedule_slots;
  v_post     jsonb;
  v_email    text;
  v_post_id  uuid;
  v_opened   integer := 0;
  v_previous text := current_setting('request.jwt.claims', true);
begin
  for v_slot in
    select * from prompts_private.schedule_slots
     where state = 'ready' and opens_at <= now()
     order by opens_at
       for update skip locked
  loop
    begin
      if v_slot.lock_at <= now() then
        raise exception 'Lock time passed before it opened';
      end if;
      select email into v_email from auth.users where id = v_slot.author_id;
      if v_email is null then
        raise exception 'The admin who marked it ready no longer exists';
      end if;
      perform set_config(
        'request.jwt.claims',
        json_build_object('sub', v_slot.author_id::text, 'email', v_email, 'role', 'authenticated')::text,
        true
      );
      v_post := v_slot.payload -> 'post';
      v_post_id := prompts.create_post(
        v_post ->> 'p_template_kind',
        v_post ->> 'p_template_name',
        v_post ->> 'p_caption',
        v_post ->> 'p_prompt_text',
        v_post ->> 'p_resolution_criteria',
        v_slot.lock_at,
        v_post -> 'p_slots',
        v_post -> 'p_resolution_source',
        coalesce((v_post ->> 'p_is_opinion')::boolean, false),
        case when jsonb_typeof(v_post -> 'p_cover_team_codes') = 'array'
             then array(select jsonb_array_elements_text(v_post -> 'p_cover_team_codes')) end,
        coalesce((v_post ->> 'p_send_push')::boolean, true)
      );
      update prompts_private.schedule_slots
         set state = 'published', post_id = v_post_id, publish_error = null, updated_at = now()
       where id = v_slot.id;
      v_opened := v_opened + 1;
    exception when others then
      update prompts_private.schedule_slots
         set state = 'draft', publish_error = sqlerrm, updated_at = now()
       where id = v_slot.id;
    end;
  end loop;
  perform set_config('request.jwt.claims', coalesce(v_previous, ''), true);
  return v_opened;
end;
$$;

revoke all on function prompts_private.promote_scheduled_tick() from public, anon, authenticated;

-- ----------------------------------------------------------------- digest --

-- What the daily email says, or null when nothing needs attention. Service role
-- only; the send-schedule-digest Edge Function is the one caller. Slots due
-- today (US Eastern) are listed apart from the ones due in the next 2 days.
create function public.claim_schedule_digest()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_items      jsonb;
  v_recipients jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id, 'kind', v.kind, 'game_id', v.game_id, 'state', v.state,
           'due_at', v.due_at, 'lock_at', v.lock_at, 'attention', v.attention,
           'today', (v.due_at at time zone 'America/New_York')::date = (now() at time zone 'America/New_York')::date
         ) order by v.due_at), '[]'::jsonb)
    into v_items
    from prompts_private.schedule_slot_view v
   where v.needs_attention;

  if jsonb_array_length(v_items) = 0 then
    return null;
  end if;

  select coalesce(jsonb_agg(lower(email)), '[]'::jsonb) into v_recipients from prompts_private.admin_config;
  if jsonb_array_length(v_recipients) = 0 then
    return null;
  end if;
  return jsonb_build_object('recipients', v_recipients, 'items', v_items);
end;
$$;

revoke all on function public.claim_schedule_digest() from public, anon, authenticated;
grant execute on function public.claim_schedule_digest() to service_role;

-- Wakes the send-schedule-digest Edge Function once a day. Like push_drain_tick
-- (0206) it reads its URL and shared secret from Vault ('digest_function_url',
-- 'digest_function_secret') and does nothing until they are set. It only calls
-- out when there is something to say.
create function prompts_private.schedule_digest_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'digest_function_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'digest_function_secret';
  if v_url is null or v_secret is null then
    return;
  end if;
  if not exists (select 1 from prompts_private.schedule_slot_view where needs_attention) then
    return;
  end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-digest-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
exception when others then
  raise warning 'schedule_digest_tick failed: %', sqlerrm;
end;
$$;

revoke all on function prompts_private.schedule_digest_tick() from public, anon, authenticated;

-- ------------------------------------------------------------------- cron --

create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('promote-scheduled', '* * * * *', $$ select prompts_private.promote_scheduled_tick() $$);
-- 05:00 Eastern in winter, 06:00 in summer; the slots exist well before they matter.
select cron.schedule('schedule-prefill', '0 10 * * *', $$ select prompts_private.schedule_prefill() $$);
-- 08:00 Eastern in winter, 09:00 in summer.
select cron.schedule('schedule-digest', '0 13 * * *', $$ select prompts_private.schedule_digest_tick() $$);

select prompts_private.schedule_prefill();
