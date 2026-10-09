-- A searchable directory of every rostered NFL player, for the open player
-- search in Weekly Awards and the `player` tag on Bold Predictions.
--
-- private.player_seasons (0099's source) can't back that: it holds only
-- QB/RB/WR/TE from 2025, no defenders or kickers, no current rosters. nflverse
-- publishes a per-season roster file with every position, the player's team
-- and headshot and a roster status, so this loads it the same way 0119 loads
-- the schedule: pg_net queues a download, a later cron tick collects it.
--
-- Rosters change slowly, so the tick runs often but only queues a download when
-- the last good load is more than a week old (or there is none yet), and waits
-- an hour after any attempt before trying again.

create table prompts_private.nfl_players (
  -- nflverse's gsis_id, e.g. '00-0033873'; stable across teams and seasons.
  player_id     text primary key,
  display_name  text not null,
  -- Lower-cased, accent-stripped copy of display_name that search reads, so a
  -- query for "jose" finds "José" without paying for the fold on every row.
  search_name   text not null,
  position      text not null,
  team          text not null,
  headshot_url  text,
  -- nflverse roster status: ACT active, DEV practice squad, RES reserve (injured
  -- reserve, PUP, NFI, suspended), INA inactive, EXE exempt. Released (CUT) and
  -- retired (RET) players are not loaded: they are no longer on a roster.
  status        text not null,
  season        smallint not null,
  updated_at    timestamptz not null default now()
);

create index nfl_players_search_name_idx on prompts_private.nfl_players (search_name text_pattern_ops);

revoke all on table prompts_private.nfl_players from public, anon, authenticated;
alter table prompts_private.nfl_players enable row level security;
-- No policies, like prompts_private.nflverse_poll (0096): clients reach it only
-- through prompts.search_players.

create extension if not exists unaccent with schema extensions;

-- Singleton, same shape as prompts_private.nflverse_poll.
create table prompts_private.roster_poll (
  id           boolean primary key default true check (id),
  request_id   bigint,
  requested_at timestamptz,
  synced_at    timestamptz
);
insert into prompts_private.roster_poll (id) values (true);

revoke all on table prompts_private.roster_poll from public, anon, authenticated;
alter table prompts_private.roster_poll enable row level security;

-- Replaces the directory with the players in a roster_<season>.csv and returns
-- how many rows it holds afterwards. Takes CSV text, not a URL, so it is
-- testable without the network. Columns are found by name; a feed that loses
-- one we need raises rather than writing nulls. Idempotent: a second load of the
-- same file changes nothing, and a player missing from a newer file (cut,
-- retired) is removed.
create or replace function prompts_private.sync_nfl_players(p_csv text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lines    text[] := string_to_array(p_csv, E'\n');
  v_header   text[] := prompts_private.csv_fields(coalesce(v_lines[1], ''));
  v_name     text;
  i_season   int;
  i_team     int;
  i_position int;
  i_status   int;
  i_name     int;
  i_id       int;
  i_headshot int;
  v_count    integer;
begin
  foreach v_name in array array['season', 'team', 'position', 'status', 'full_name', 'gsis_id', 'headshot_url'] loop
    if array_position(v_header, v_name) is null then
      raise exception 'nflverse roster is missing the % column', v_name;
    end if;
  end loop;

  i_season := array_position(v_header, 'season');
  i_team := array_position(v_header, 'team');
  i_position := array_position(v_header, 'position');
  i_status := array_position(v_header, 'status');
  i_name := array_position(v_header, 'full_name');
  i_id := array_position(v_header, 'gsis_id');
  i_headshot := array_position(v_header, 'headshot_url');

  create temporary table if not exists pg_temp.roster_load (
    player_id text, display_name text, position text, team text,
    headshot_url text, status text, season smallint
  ) on commit drop;
  truncate pg_temp.roster_load;

  insert into pg_temp.roster_load
  select distinct on (f[i_id]) f[i_id], f[i_name], f[i_position], f[i_team],
         nullif(f[i_headshot], ''), f[i_status], f[i_season]::smallint
    from (
      select prompts_private.csv_fields(l) as f
        from unnest(v_lines[2:]) as l
       where l <> ''
    ) parsed
   where f[i_id] <> '' and f[i_name] <> '' and f[i_team] <> '' and f[i_position] <> ''
     and f[i_status] not in ('CUT', 'RET')
   order by f[i_id];

  -- An empty or all-cut file would otherwise wipe the directory.
  select count(*) into v_count from pg_temp.roster_load;
  if v_count = 0 then
    raise exception 'nflverse roster has no rostered players';
  end if;

  delete from prompts_private.nfl_players p
   where not exists (select 1 from pg_temp.roster_load l where l.player_id = p.player_id);

  insert into prompts_private.nfl_players
    (player_id, display_name, search_name, position, team, headshot_url, status, season)
  select l.player_id, l.display_name, lower(extensions.unaccent(l.display_name)),
         l.position, l.team, l.headshot_url, l.status, l.season
    from pg_temp.roster_load l
  on conflict (player_id) do update
     set display_name = excluded.display_name, search_name = excluded.search_name,
         position = excluded.position, team = excluded.team,
         headshot_url = excluded.headshot_url, status = excluded.status,
         season = excluded.season, updated_at = now()
   where (prompts_private.nfl_players.display_name, prompts_private.nfl_players.position,
          prompts_private.nfl_players.team, prompts_private.nfl_players.headshot_url,
          prompts_private.nfl_players.status, prompts_private.nfl_players.season)
         is distinct from
         (excluded.display_name, excluded.position, excluded.team,
          excluded.headshot_url, excluded.status, excluded.season);

  return v_count;
end;
$$;

-- Collects the previous tick's download, then queues the next one if the
-- directory is due a refresh. The sync's failures are caught so a changed feed
-- shows up as a warning and a retry in an hour, never a stuck cron job.
create or replace function prompts_private.nfl_roster_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll    prompts_private.roster_poll;
  v_status  int;
  v_content text;
  v_found   boolean;
  v_season  int;
begin
  select * into v_poll from prompts_private.roster_poll where id;

  if v_poll.request_id is not null then
    select r.status_code, r.content, true into v_status, v_content, v_found
      from net._http_response r
     where r.id = v_poll.request_id;

    if v_found then
      if v_status = 200 then
        begin
          perform prompts_private.sync_nfl_players(v_content);
          v_poll.synced_at := now();
        exception when others then
          raise warning 'nfl_roster_sync_failed sqlerrm=%', sqlerrm;
        end;
      end if;
      update prompts_private.roster_poll set request_id = null, synced_at = v_poll.synced_at where id;
      v_poll.request_id := null;
    elsif v_poll.requested_at < now() - interval '15 minutes' then
      -- The worker never answered; stop waiting on it.
      update prompts_private.roster_poll set request_id = null where id;
      v_poll.request_id := null;
    end if;
  end if;

  if v_poll.request_id is null
     and (v_poll.synced_at is null or v_poll.synced_at < now() - interval '7 days')
     and (v_poll.requested_at is null or v_poll.requested_at < now() - interval '1 hour') then
    -- The league year starts in March; before that the season is last year's.
    v_season := extract(year from now() - interval '2 months');
    update prompts_private.roster_poll
       set request_id = net.http_get(
             url := format('https://github.com/nflverse/nflverse-data/releases/download/rosters/roster_%s.csv', v_season),
             timeout_milliseconds := 30000
           ),
           requested_at = now()
     where id;
  end if;
end;
$$;

revoke all on function prompts_private.sync_nfl_players(text) from public, anon, authenticated;
revoke all on function prompts_private.nfl_roster_tick()      from public, anon, authenticated;

-- Every 10 minutes: cheap when nothing is due, and a fresh project or a failed
-- download is picked up within a cycle.
select cron.schedule('nfl-roster-refresh', '*/10 * * * *', $$ select prompts_private.nfl_roster_tick() $$);

-- Type-ahead search over the directory. Any signed-in, non-guest user may call
-- it (the same bar as posting a take, 0095); it returns identity fields only.
-- Every word of the query must appear in the name, accents and case ignored;
-- names that start with the query rank first, then names with a word starting
-- with it, then plain substrings, and within a rank active players come before
-- practice-squad and reserve ones.
create function prompts.search_players(p_query text, p_limit integer default 20)
returns table (
  player_id text,
  display_name text,
  "position" text,
  team text,
  headshot_url text,
  status text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_query  text := lower(extensions.unaccent(btrim(coalesce(p_query, ''))));
  v_tokens text[];
begin
  if auth.uid() is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  v_tokens := array(
    select replace(replace(replace(t, '\', '\\'), '%', '\%'), '_', '\_')
      from unnest(regexp_split_to_array(v_query, '\s+')) as t
     where t <> ''
  );
  if cardinality(v_tokens) = 0 then
    return;
  end if;

  return query
  select p.player_id, p.display_name, p.position, p.team, p.headshot_url, p.status
    from prompts_private.nfl_players p
   where not exists (
           select 1 from unnest(v_tokens) t where p.search_name not like '%' || t || '%'
         )
   order by
     case
       when p.search_name like array_to_string(v_tokens, ' ') || '%' then 0
       when not exists (
              select 1 from unnest(v_tokens) t
               where ' ' || p.search_name not like '% ' || t || '%'
            ) then 1
       else 2
     end,
     case p.status when 'ACT' then 0 when 'DEV' then 1 else 2 end,
     p.display_name,
     p.player_id
   limit greatest(1, least(coalesce(p_limit, 20), 50));
end;
$$;

revoke all on function prompts.search_players(text, integer) from public, anon;
grant execute on function prompts.search_players(text, integer) to authenticated;

select prompts_private.nfl_roster_tick();
