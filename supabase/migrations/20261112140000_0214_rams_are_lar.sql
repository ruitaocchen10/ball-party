-- The Rams are LAR everywhere, not nflverse's LA, so a team code can never be
-- mistaken for the Chargers' LAC. This rewrites the data that carries a team
-- code, makes the two nflverse importers speak LAR from now on, and has
-- is_valid_team_code accept LAR instead of LA.
--
-- Keys that are not team codes are left alone: game ids (2026_05_BUF_LA are
-- nflverse's), the Pro Football Reference logo codes (ram) and the historic
-- franchise code STL.
--
-- Run it once; every statement is idempotent.

-- ------------------------------------------------------------ validation --

create or replace function prompts_private.is_valid_team_code(p_code text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_code = any (array[
    'BUF','MIA','NE','NYJ','KC','LV','LAC','DEN','BAL','CIN','CLE','PIT','HOU','IND','JAX','TEN',
    'SEA','SF','LAR','ARI','PHI','DAL','NYG','WAS','CHI','DET','GB','MIN','ATL','CAR','NO','TB'
  ]);
$$;

-- --------------------------------------------------------------- importers --

-- The Rams are LAR here, not nflverse's LA, so they cannot be mistaken for the
-- Chargers (LAC). The game id (e.g. 2026_05_BUF_LA) is nflverse's key and is kept.
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
           case f[i_away] when 'LA' then 'LAR' else f[i_away] end as away_team,
           case f[i_home] when 'LA' then 'LAR' else f[i_home] end as home_team,
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

-- The Rams are LAR here, not nflverse's LA (see sync_nfl_games).
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
  select distinct on (f[i_id]) f[i_id], f[i_name], f[i_position], case f[i_team] when 'LA' then 'LAR' else f[i_team] end,
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

-- -------------------------------------------------------------------- data --

update public.nfl_games set home_team = 'LAR' where home_team = 'LA';
update public.nfl_games set away_team = 'LAR' where away_team = 'LA';
update prompts_private.nfl_players set team = 'LAR' where team = 'LA';

-- Option pools, ballots' pools and the Power Rankings cover.
update public.prompt_slot_options set team_code = 'LAR' where team_code = 'LA';
update public.prompt_posts set cover_team_codes = array_replace(cover_team_codes, 'LA', 'LAR')
 where 'LA' = any (cover_team_codes);

-- Bold Predictions tagged to a team.
update public.bold_predictions set target_id = 'LAR' where target_type = 'team' and target_id = 'LA';

-- Ranking lists built from prompt answers before this ran (0212's backfill).
update public.ranking_list_items set team_code = 'LAR' where team_code = 'LA';

-- Game content.
update public.auction_lots set team = 'LAR' where team = 'LA';
update public.auction_lots set opponent = 'LAR' where opponent = 'LA';
update public.higher_or_lower_cards set team = 'LAR' where team = 'LA';
update public.higher_or_lower_cards set opponent = 'LAR' where opponent = 'LA';
update private.player_seasons set team = 'LAR' where team = 'LA';
update private.player_weeks set team = 'LAR' where team = 'LA';
update private.player_weeks set opponent = 'LAR' where opponent = 'LA';
