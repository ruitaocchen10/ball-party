-- Automatic resolution for game_pick posts: a periodic sweep (same
-- cron.schedule idiom as 0016's guest cleanup and 0033's higher-or-lower
-- clock) that reads the real final score off nflverse's public schedule
-- release and calls the same grading path resolve_post (0095) already uses,
-- instead of waiting on an admin.
--
-- Deliberately NOT ESPN's API, which was the first thing tried: pg_net's
-- requests to it came back 403 from Akamai even with a browser User-Agent
-- and from the same IP a plain curl succeeded from — a client-fingerprint
-- block, not a rate limit or a missing header, and not something worth
-- fighting for a hobby project. nflverse's release asset is a plain HTTPS
-- file download over GitHub's CDN with no such gate, and its schedule file
-- specifically refreshes every 5 minutes in-season (nflreadr's own
-- documented cadence) — same-day, not "wait for the nightly stats drop."
-- stat_leader/ranking/custom_multi have no equally mechanical answer to
-- derive this way, so they're left for prompts.resolve_post regardless —
-- see 0094's comment on resolution_source.
--
-- Split into two functions for one reason: net.http_get only queues a
-- request (net._http_response fills in asynchronously, from a worker
-- process outside this transaction), so a single function cannot issue the
-- request and read its own answer back in the same call — the row it just
-- inserted isn't visible to that worker until this transaction commits.
-- auto_resolve_tick instead straddles two ticks: each run first collects
-- whatever the *previous* tick's request produced, then queues the next
-- one. grade_due_game_picks takes plain CSV text rather than doing the
-- fetch itself so it can be unit tested without the network — see
-- supabase/tests/0096_prompts_auto_resolve.test.sql.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Singleton: one outstanding request tracked at a time, since one file
-- covers every game a post could be waiting on — there's never a reason to
-- have two schedule fetches in flight together.
create table prompts_private.nflverse_poll (
  id           boolean primary key default true check (id),
  request_id   bigint,
  requested_at timestamptz
);
insert into prompts_private.nflverse_poll (id) values (true);

revoke all on table prompts_private.nflverse_poll from public, anon, authenticated;
alter table prompts_private.nflverse_poll enable row level security;
-- No policies: same posture as prompts_private.admin_config (0095) — only
-- reachable through the security definer functions below.

create or replace function prompts_private.grade_due_game_picks(p_csv text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post          public.prompt_posts;
  v_line          text;
  v_away_team     text;
  v_away_score    text;
  v_home_team     text;
  v_home_score    text;
  v_winner_code   text;
  v_slot          record;
  v_winner_option uuid;
  v_answers       jsonb;
  v_incomplete    boolean;
begin
  -- status = 'locked' is what this ought to filter on, but nothing in
  -- 0094/0095 ever writes that value yet — lock_at is checked live against
  -- now() (see submit_response), not mirrored onto status by any sweep. So
  -- this reads the same live condition submit_response enforces, and picks
  -- up 'locked' too the day a sweep starts setting it.
  for v_post in
    select * from public.prompt_posts
     where status in ('open', 'locked')
       and lock_at <= now()
       and resolved_at is null
       and template_kind = 'game_pick'
       and resolution_source is not null
  loop
    begin
      select l into v_line
        from unnest(string_to_array(p_csv, E'\n')) as l
       where l like (v_post.resolution_source ->> 'game_id') || ',%'
       limit 1;

      continue when v_line is null;

      v_away_team  := split_part(v_line, ',', 8);
      v_away_score := split_part(v_line, ',', 9);
      v_home_team  := split_part(v_line, ',', 10);
      v_home_score := split_part(v_line, ',', 11);

      continue when v_away_score = '' or v_home_score = '';
      continue when v_away_score = v_home_score;

      v_winner_code := case when v_home_score::int > v_away_score::int then v_home_team else v_away_team end;

      v_answers := '{}'::jsonb;
      v_incomplete := false;

      for v_slot in select * from public.prompt_slots where post_id = v_post.id loop
        select id into v_winner_option
          from public.prompt_slot_options
         where slot_id = v_slot.id and team_code = v_winner_code;

        if v_winner_option is null then
          v_incomplete := true;
          exit;
        end if;

        v_answers := v_answers || jsonb_build_object(v_slot.id::text, jsonb_build_array(v_winner_option::text));
      end loop;

      continue when v_incomplete;

      perform prompts_private.do_resolve(v_post.id, v_answers);
    exception when others then
      raise warning 'auto_resolve_failed post_id=% sqlerrm=%', v_post.id, sqlerrm;
    end;
  end loop;
end;
$$;

create or replace function prompts_private.auto_resolve_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll    prompts_private.nflverse_poll;
  v_status  int;
  v_content text;
begin
  select * into v_poll from prompts_private.nflverse_poll where id;

  if v_poll.request_id is not null then
    select r.status_code, r.content into v_status, v_content
      from net._http_response r
     where r.id = v_poll.request_id;

    if found and v_status = 200 then
      perform prompts_private.grade_due_game_picks(v_content);
    end if;
  end if;

  if exists (
    select 1 from public.prompt_posts
     where status in ('open', 'locked') and lock_at <= now() and resolved_at is null
       and template_kind = 'game_pick' and resolution_source is not null
  ) then
    update prompts_private.nflverse_poll
       set request_id = net.http_get(
             url := 'https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv',
             timeout_milliseconds := 20000
           ),
           requested_at = now()
     where id;
  else
    update prompts_private.nflverse_poll set request_id = null, requested_at = null where id;
  end if;
end;
$$;

-- Every 5 minutes, matching nflverse's own refresh cadence for this file —
-- polling faster would just re-read the same content.
select cron.schedule('prompts-auto-resolve', '*/5 * * * *', $$ select prompts_private.auto_resolve_tick() $$);

revoke all on function prompts_private.grade_due_game_picks(text) from public, anon, authenticated;
revoke all on function prompts_private.auto_resolve_tick()        from public, anon, authenticated;
