-- The NFL regular-season schedule as a table both clients read.
--
-- A matchup cover shows the venue, the kickoff time and a Primetime flag.
-- Until now the web got those by having its own server download nflverse's
-- games.csv from GitHub on every ISR refresh, which left the iOS app with a
-- game id (prompt_slots.source_game_id, 0097) and nothing to look it up in.
-- Putting the rows in Postgres makes the schedule one shared read model: the
-- web, the iOS app and the admin composer all ask the same place.
--
-- Nothing new is fetched to fill it. 0096's poll already downloads exactly this
-- file every five minutes while a game pick is waiting on a final score, so the
-- same response now also refreshes the schedule, and the poll additionally
-- fires when the schedule is more than an hour old. Kickoffs do move (Sunday
-- night flex), hence an hourly refresh rather than a one-time load.

create table public.nfl_games (
  -- nflverse's game_id, e.g. '2026_02_BUF_KC' — the same value a slot keeps in
  -- prompt_slots.source_game_id.
  id         text primary key,
  season     smallint not null,
  week       smallint not null,
  kickoff    timestamptz not null,
  away_team  text not null,
  home_team  text not null,
  -- Official venue; matters for neutral-site games. Empty when the feed has none.
  stadium    text not null default '',
  -- The Thursday, Sunday and Monday national evening windows (kickoff at or
  -- after 19:00 Eastern). The feed has no broadcast-window column to read.
  primetime  boolean not null default false,
  updated_at timestamptz not null default now()
);

create index nfl_games_season_week_kickoff_idx on public.nfl_games (season, week, kickoff);

alter table public.nfl_games enable row level security;

-- Public schedule data, readable by a signed-out visitor for the same reason
-- the Huddle is (0112). Writes happen only in prompts_private.sync_nfl_games,
-- a security definer function, so no insert/update/delete grant or policy
-- exists for a client role.
revoke all on table public.nfl_games from public, anon, authenticated;
grant select on public.nfl_games to anon, authenticated;
create policy nfl_games_select_public on public.nfl_games
  for select to anon, authenticated using (true);

-- One CSV row as its fields. nflverse quotes a value that holds a comma or
-- writes an empty one as "" (the `surface` column), so a plain split on commas
-- is not enough; a doubled quote inside a quoted value is a literal quote.
create or replace function prompts_private.csv_fields(p_line text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(
           case when m[1] is not null then replace(m[1], '""', '"') else m[2] end
           order by ord
         ), '{}')
    from regexp_matches(rtrim(p_line, E'\r'), '(?:^|,)(?:"((?:[^"]|"")*)"|([^,]*))', 'g')
         with ordinality as t(m, ord)
$$;

-- Upserts every regular-season game in a games.csv into public.nfl_games and
-- returns how many rows were inserted or changed. Takes CSV text, not a URL,
-- for the same reason grade_due_game_picks does: so it is testable without the
-- network. Columns are found by name in the header, so a reordered or widened
-- feed keeps working; a feed that loses one we need raises instead of quietly
-- writing nulls.
create or replace function prompts_private.sync_nfl_games(p_csv text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lines   text[] := string_to_array(p_csv, E'\n');
  v_header  text[] := prompts_private.csv_fields(coalesce(v_lines[1], ''));
  v_name    text;
  i_id      int;
  i_season  int;
  i_type    int;
  i_week    int;
  i_day     int;
  i_time    int;
  i_away    int;
  i_home    int;
  i_stadium int;
  v_changed integer;
begin
  foreach v_name in array array['game_id', 'season', 'game_type', 'week', 'gameday', 'gametime', 'away_team', 'home_team', 'stadium'] loop
    if array_position(v_header, v_name) is null then
      raise exception 'nflverse schedule is missing the % column', v_name;
    end if;
  end loop;

  i_id := array_position(v_header, 'game_id');
  i_season := array_position(v_header, 'season');
  i_type := array_position(v_header, 'game_type');
  i_week := array_position(v_header, 'week');
  i_day := array_position(v_header, 'gameday');
  i_time := array_position(v_header, 'gametime');
  i_away := array_position(v_header, 'away_team');
  i_home := array_position(v_header, 'home_team');
  i_stadium := array_position(v_header, 'stadium');

  -- MATERIALIZED, because `candidates` reads `f` nine times and Postgres would
  -- otherwise inline the parse into each read and run it nine times per row.
  with parsed as materialized (
    -- ',REG,' is only a cheap way to skip the playoff and preseason rows
    -- before paying for a full parse; the exact game_type check is below.
    select prompts_private.csv_fields(l) as f
      from unnest(v_lines[2:]) as l
     where strpos(l, ',REG,') > 0
  ),
  candidates as (
    select f[i_id] as id,
           f[i_type] as game_type,
           -- Guarded casts: the CASE keeps a malformed value from raising
           -- instead of the row being skipped.
           case when f[i_season] ~ '^\d{4}$' then f[i_season]::smallint end as season,
           case when f[i_week] ~ '^\d{1,2}$' then f[i_week]::smallint end as week,
           -- gameday and gametime are an Eastern wall-clock time, not UTC.
           case when f[i_day] ~ '^\d{4}-\d{2}-\d{2}$' and f[i_time] ~ '^\d{1,2}:\d{2}(:\d{2})?$'
                then (f[i_day] || ' ' || f[i_time])::timestamp end as eastern,
           f[i_away] as away_team,
           f[i_home] as home_team,
           coalesce(f[i_stadium], '') as stadium
      from parsed
  )
  insert into public.nfl_games as g (id, season, week, kickoff, away_team, home_team, stadium, primetime)
  select distinct on (id)
         id, season, week,
         eastern at time zone 'America/New_York',
         away_team, home_team, stadium,
         -- dow 0 is Sunday, 1 Monday, 4 Thursday.
         extract(dow from eastern) in (0, 1, 4) and extract(hour from eastern) >= 19
    from candidates
   where game_type = 'REG'
     and id <> '' and away_team <> '' and home_team <> ''
     and season is not null and week is not null and eastern is not null
   order by id
  on conflict (id) do update
     set season = excluded.season,
         week = excluded.week,
         kickoff = excluded.kickoff,
         away_team = excluded.away_team,
         home_team = excluded.home_team,
         stadium = excluded.stadium,
         primetime = excluded.primetime,
         updated_at = now()
   where (g.season, g.week, g.kickoff, g.away_team, g.home_team, g.stadium, g.primetime)
         is distinct from (excluded.season, excluded.week, excluded.kickoff, excluded.away_team,
                           excluded.home_team, excluded.stadium, excluded.primetime);

  get diagnostics v_changed = row_count;
  return v_changed;
end;
$$;

-- When the schedule was last refreshed, kept on 0096's singleton because that
-- is the one place the in-flight games.csv request is already tracked.
alter table prompts_private.nflverse_poll add column schedule_synced_at timestamptz;

-- 0096's tick, extended in two ways: a response that arrives is also synced
-- into nfl_games, and a request is queued when the schedule is stale as well
-- as when a pick is waiting on a score. The sync sits in its own sub-block so a
-- change in the feed that breaks it can never stop picks from grading.
create or replace function prompts_private.auto_resolve_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll     prompts_private.nflverse_poll;
  v_status   int;
  v_content  text;
  v_synced   timestamptz;
begin
  select * into v_poll from prompts_private.nflverse_poll where id;
  v_synced := v_poll.schedule_synced_at;

  if v_poll.request_id is not null then
    select r.status_code, r.content into v_status, v_content
      from net._http_response r
     where r.id = v_poll.request_id;

    if found and v_status = 200 then
      perform prompts_private.grade_due_game_picks(v_content);

      begin
        perform prompts_private.sync_nfl_games(v_content);
        v_synced := now();
        update prompts_private.nflverse_poll set schedule_synced_at = v_synced where id;
      exception when others then
        raise warning 'nfl_schedule_sync_failed sqlerrm=%', sqlerrm;
      end;
    end if;
  end if;

  if v_synced is null or v_synced < now() - interval '1 hour' or exists (
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

revoke all on function prompts_private.csv_fields(text)      from public, anon, authenticated;
revoke all on function prompts_private.sync_nfl_games(text)  from public, anon, authenticated;
revoke all on function prompts_private.auto_resolve_tick()   from public, anon, authenticated;

-- Queue the first download now rather than waiting up to five minutes for the
-- cron job's next tick; that tick then collects it, so a fresh project has its
-- schedule within one cycle of deploying this.
select prompts_private.auto_resolve_tick();
