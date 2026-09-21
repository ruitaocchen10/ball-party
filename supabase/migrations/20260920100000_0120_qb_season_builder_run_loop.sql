-- QB Season Builder: its schema pair, the finished rating data the game reads,
-- and the first half of the run loop — start a run, deal the first spin, read
-- the run's state. See issue #74 (sub-issue of #72).
--
-- THIS SLICE IS THE DEAL. Picking is 0121, the respin is 0122. Season
-- generation and the result are a later ticket; a run whose six slots are
-- filled just becomes ready to finish.
--
-- Same shape as the other server-authoritative games (0029, 0032, 0051):
--
--   qb_season_builder          the write API a client may call. Exposed via
--                              PostgREST, so it holds nothing not meant to be
--                              reachable.
--   qb_season_builder_private  the rules engine and the finished ratings. Not
--                              in the exposed schema list and no usage granted
--                              to anon or authenticated: unreachable, not
--                              merely unrouted.
--
-- Exposing the public one also takes an entry in `[api] schemas` in
-- config.toml AND the hosted project's exposed-schema dashboard setting, which
-- no migration can carry — see supabase/README.md.
--
-- THE RATINGS ARE PRIVATE, and that is what makes hidden mode real. Hiding a
-- value is enforced by what the API returns, not by the UI, so no table a
-- client can select from may hold one. The two rating tables below live in the
-- private schema; a value reaches a client only through
-- qb_season_builder_private.board_of, which decides per run whether to show it.
-- The picks a run makes are split the same way: which slot took which source
-- is a public fact (public.qb_season_builder_picks), the number it was worth is
-- not (qb_season_builder_private.pick_values).
--
-- NOTHING HERE IS PUBLISHED TO REALTIME, unlike the sabotage draft's tables
-- (0051). A solo run has no other player to fan a change out to; the one client
-- that plays it reads the whole run through qb_season_builder.state after each
-- call, and a hidden run's numbers never sit on a replicated row anyway.
--
-- SPINS ARE DEALT ONE ROUND AT A TIME, when the round opens, not all six up
-- front. A future round's spin therefore does not exist to be read, by any
-- role, rather than existing and being hidden by a policy. (Sabotage draft
-- deals everything at once and hides by policy, 0064; there a franchise is
-- public information from the start of the round. Here there is no seed and no
-- reason to hold a spin that may never be reached.) The spins policy still
-- gates on the current round, so a row that ever did exist ahead of its round
-- would stay unreadable.

-- ------------------------------------------------------------------ the name --
-- `matches.game` is the platform's registry of games that exist at all.
alter table public.matches drop constraint matches_game_check;
alter table public.matches add constraint matches_game_check check (game in (
  'auction_team_builder',
  'cards_against_humanity',
  'higher_or_lower',
  'wavelength_2v2',
  'sabotage_draft',
  'qb_season_builder'
));

-- ------------------------------------------------------------------ schemas --

create schema if not exists qb_season_builder;
create schema if not exists qb_season_builder_private;

revoke all on schema qb_season_builder_private from public, anon, authenticated;

revoke all on schema qb_season_builder from public;
grant usage on schema qb_season_builder to anon, authenticated, service_role;

-- ----------------------------------------------------------- the ratings --

-- One row per team-season: its Supporting Cast value, 0-99. `franchise_code`
-- is Pro Football Reference's stable code, the same one private.av_roster_players
-- uses, so a relocated franchise is one code across years.
--
-- Loaded by the ratings pipeline (a later ticket) through a migration; the
-- rows a fresh database holds until then are local fixtures only (seed.sql).
create table qb_season_builder_private.team_seasons (
  franchise_code  text     not null,
  season          smallint not null check (season between 2006 and 2025),
  supporting_cast smallint not null check (supporting_cast between 0 and 99),

  primary key (franchise_code, season)
);

-- One row per qualifying quarterback-season with its five quality values,
-- 0-99. The pipeline decides who qualifies (roughly 150 or more pass attempts)
-- before a row is written, so *having a row* is what qualifying means here:
-- a spin draws from the team-seasons that have at least one. A quarterback who
-- played for two teams in a season is one row per team.
create table qb_season_builder_private.qb_seasons (
  franchise_code text     not null,
  season         smallint not null,
  player_id      text     not null,
  display_name   text     not null,
  accuracy       smallint not null check (accuracy   between 0 and 99),
  arm_talent     smallint not null check (arm_talent between 0 and 99),
  mobility       smallint not null check (mobility   between 0 and 99),
  iq             smallint not null check (iq         between 0 and 99),
  build          smallint not null check (build      between 0 and 99),

  primary key (franchise_code, season, player_id),
  -- Every quarterback-season sits on a team-season that has a Supporting Cast,
  -- so a spin can always offer the cast as one of its sources.
  foreign key (franchise_code, season)
    references qb_season_builder_private.team_seasons (franchise_code, season)
);

alter table qb_season_builder_private.team_seasons enable row level security;
alter table qb_season_builder_private.qb_seasons   enable row level security;
revoke all on table qb_season_builder_private.team_seasons from public, anon, authenticated;
revoke all on table qb_season_builder_private.qb_seasons   from public, anon, authenticated;

-- ------------------------------------------------------------ the run tables --

-- The run's own state. `mode` is chosen at start and there is no function that
-- writes it again. `drafted_at` is set when the sixth slot is filled: the run
-- is then ready to finish, and there is no seventh round to open.
create table public.qb_season_builder_matches (
  match_id      uuid        primary key references public.matches (id) on delete cascade,
  mode          text        not null check (mode in ('visible', 'hidden')),
  round_count   smallint    not null default 6 check (round_count = 6),
  current_round smallint    not null default 1 check (current_round between 1 and round_count),
  respin_used   boolean     not null default false,
  drafted_at    timestamptz
);

-- A round's spin: a team-season, stored with the run so a reload or a second
-- client sees the same one. `attempt` is 1 for the deal and 2 for the respin,
-- which replaces the spin as far as play goes but does not erase it — a hidden
-- run reveals every option the player was shown, and a respun-away spin was
-- shown. The current spin is the highest attempt of the current round.
create table public.qb_season_builder_spins (
  match_id       uuid     not null references public.matches (id) on delete cascade,
  round_number   smallint not null check (round_number between 1 and 6),
  attempt        smallint not null default 1 check (attempt in (1, 2)),
  franchise_code text     not null,
  season         smallint not null check (season between 2006 and 2025),

  primary key (match_id, round_number, attempt)
);

-- ------------------------------------------------------------------- the deal --

-- Draw one team-season uniformly from those with at least one qualifying
-- quarterback — every (franchise, season) that has a row in qb_seasons, and
-- nothing else, so a team-season with a Supporting Cast and nobody who
-- qualified can never come up. No exclusion set across rounds: the same
-- team-season may come up more than once in a game. The optional exclusion is
-- for the respin, which must land somewhere else to be worth spending.
create function qb_season_builder_private.draw_spin(
  p_exclude_franchise text default null,
  p_exclude_season    smallint default null
)
returns table (franchise_code text, season smallint)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return query
    select q.franchise_code, q.season
      from (
        select distinct s.franchise_code, s.season
          from qb_season_builder_private.qb_seasons s
      ) q
     where p_exclude_franchise is null
        or (q.franchise_code, q.season) <> (p_exclude_franchise, p_exclude_season)
     order by random()
     limit 1;

  if not found then
    raise exception 'pool_exhausted' using errcode = 'P0001';
  end if;
end;
$$;

-- ------------------------------------------------------------ the projection --

-- What a client is told about a run. A projection, not a table: adding a
-- column anywhere must never silently also be a decision to publish it.
--
--   phase      'picking' while a round is open, 'ready_to_finish' once all six
--              slots are filled
--   franchise_code, season, options
--              the current round's spin and what it offers; null when no round
--              is open. `options` is
--                {"quarterbacks": [{"player_id", "display_name", "values": {...}|null}],
--                 "supporting_cast": {"value": n|null}}
--              and every value is null in a hidden run until it is finished.
--   picks      the filled slots, oldest first, with the same rule on `value`
create type qb_season_builder.board as (
  match_id       uuid,
  mode           text,
  phase          text,
  round_count    smallint,
  current_round  smallint,
  respin_used    boolean,
  franchise_code text,
  season         smallint,
  options        jsonb,
  picks          jsonb
);

-- The current round's spin: the highest attempt dealt for it (the respin, when
-- one has been spent). Read by the projection, by pick and by respin, so there
-- is one definition of "the spin in play".
create function qb_season_builder_private.current_spin_of(p_match_id uuid, p_round smallint)
returns public.qb_season_builder_spins
language sql
stable
security definer
set search_path = ''
as $$
  select s from public.qb_season_builder_spins s
   where s.match_id = p_match_id and s.round_number = p_round
   order by s.attempt desc
   limit 1;
$$;

-- What a spin offers: its qualifying quarterbacks with their five qualities, and
-- the team's Supporting Cast. The one place the ratings are turned into JSON, and
-- so the one place a hidden run's numbers are withheld: with p_reveal false every
-- value is null but the quarterbacks themselves are still named.
create function qb_season_builder_private.options_of(
  p_franchise_code text, p_season smallint, p_reveal boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'quarterbacks', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'player_id',    q.player_id,
                 'display_name', q.display_name,
                 'values', case when p_reveal then jsonb_build_object(
                   'accuracy',   q.accuracy,
                   'arm_talent', q.arm_talent,
                   'mobility',   q.mobility,
                   'iq',         q.iq,
                   'build',      q.build
                 ) end
               )
               order by q.player_id
             )
        from qb_season_builder_private.qb_seasons q
       where q.franchise_code = p_franchise_code and q.season = p_season
    ), '[]'::jsonb),
    'supporting_cast', jsonb_build_object(
      'value', (
        select case when p_reveal then t.supporting_cast end
          from qb_season_builder_private.team_seasons t
         where t.franchise_code = p_franchise_code and t.season = p_season
      )
    )
  );
$$;

-- The guard every move on a run in play starts with: take the match's lock, then
-- check it is this game's, that the caller is its participant and that it has
-- been dealt and not ended. Returns the run's own row. The caller has already
-- established there is a session and validated its own arguments, so a bad
-- argument is refused before the lock is taken.
--
-- The lock serialises a run's moves, so two picks (or a pick and a respin) can
-- never both see the same open round.
create function qb_season_builder_private.lock_playing_run(p_match_id uuid, p_user uuid)
returns public.qb_season_builder_matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches;
  v_run   public.qb_season_builder_matches;
begin
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_match.game <> 'qb_season_builder' then
    raise exception 'wrong_game' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.run_participants
     where run_id = v_match.run_id and user_id = p_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_match.status <> 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  select * into v_run from public.qb_season_builder_matches where match_id = p_match_id;
  return v_run;
end;
$$;

-- The one place a value is either shown or withheld. A value is shown in a
-- visible run always, and in a hidden run only once the run is finished — the
-- platform's own match status ('complete') is what "complete" means, so this needs no flag
-- of its own to fall out of step with it.
create function qb_season_builder_private.board_of(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
-- Volatile on purpose: pick and respin call it after writing in the same
-- transaction and need it to see those writes, which a STABLE function only
-- does by the accident of taking a fresh snapshot per call.
security definer
set search_path = ''
as $$
declare
  v_run     public.qb_season_builder_matches;
  v_spin    public.qb_season_builder_spins;
  v_reveal  boolean;
  v_options jsonb;
begin
  select * into v_run from public.qb_season_builder_matches where match_id = p_match_id;
  if not found then
    raise exception 'match_not_started' using errcode = 'P0002';
  end if;

  v_reveal := v_run.mode = 'visible'
    or exists (
      select 1 from public.matches m
       where m.id = p_match_id and m.status = 'complete'::public.match_status
    );

  if v_run.drafted_at is null then
    v_spin := qb_season_builder_private.current_spin_of(p_match_id, v_run.current_round);
    v_options := qb_season_builder_private.options_of(v_spin.franchise_code, v_spin.season, v_reveal);
  end if;

  return (
    v_run.match_id,
    v_run.mode,
    case when v_run.drafted_at is null then 'picking' else 'ready_to_finish' end,
    v_run.round_count,
    v_run.current_round,
    v_run.respin_used,
    v_spin.franchise_code,
    v_spin.season,
    v_options,
    '[]'::jsonb
  )::qb_season_builder.board;
end;
$$;

-- The reconnect contract: whoever owns the run can ask what round it is on and
-- what that round spun, from any client, at any time — including a run they
-- walked away from. Nothing sweeps an unfinished run and there is no "continue"
-- entry point; reopening its URL is this call.
create function qb_season_builder.state(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  return qb_season_builder_private.board_of(p_match_id);
end;
$$;

-- Deals the run: locks in the mode, draws round 1's spin, opens the match.
-- Takes no seed and nothing about the spin, on purpose — a client that chose
-- either could pick its own rounds. Identity is auth.uid(), never an argument.
--
-- Called once, by the run's one participant, immediately after
-- public.start_solo_run('qb_season_builder') returns a 'setup' match. Starting
-- again is a new start_solo_run, so it is always a new run.
create function qb_season_builder.start(p_match_id uuid, p_mode text default 'visible')
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
  v_spin  record;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_mode is null or p_mode not in ('visible', 'hidden') then
    raise exception 'invalid_mode' using errcode = '22023';
  end if;

  -- The lock is what makes "deal twice" impossible rather than unlikely.
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_match.game <> 'qb_season_builder' then
    raise exception 'wrong_game' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.run_participants
     where run_id = v_match.run_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_match.status <> 'setup'::public.match_status then
    raise exception 'match_not_setup' using errcode = 'P0001';
  end if;

  insert into public.qb_season_builder_matches (match_id, mode)
  values (p_match_id, p_mode);

  select * into v_spin from qb_season_builder_private.draw_spin();
  insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
  values (p_match_id, 1, 1, v_spin.franchise_code, v_spin.season);

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  return qb_season_builder_private.board_of(p_match_id);
end;
$$;

-- ---------------------------------------------------------------------- RLS --

alter table public.qb_season_builder_matches enable row level security;
alter table public.qb_season_builder_spins   enable row level security;

-- private.is_match_member is the platform's membership helper (0010, 0044), and
-- it covers a solo run through its own roster. A guest is a member of their own
-- run the same as anyone.
create policy qb_season_builder_matches_select_member on public.qb_season_builder_matches
  for select to authenticated using (private.is_match_member(match_id));

-- A spin is readable once its round is open. Rounds are dealt when they open,
-- so this is belt and braces (see the header); it is what keeps a spin dealt
-- ahead of its round unreadable if a later change ever does that.
create policy qb_season_builder_spins_select_member on public.qb_season_builder_spins
  for select to authenticated using (
    private.is_match_member(match_id)
    and round_number <= (
      select m.current_round from public.qb_season_builder_matches m
       where m.match_id = qb_season_builder_spins.match_id
    )
  );

-- No INSERT/UPDATE/DELETE policies, consistent with every table since 0003.
-- Every write goes through a definer function.

grant select on public.qb_season_builder_matches to authenticated;
grant select on public.qb_season_builder_spins   to authenticated;

-- ---------------------------------------------------------------- privileges --
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. Take it back, then hand
-- out only what a signed-in player, guests included, is allowed to ask for.

revoke all on function qb_season_builder_private.draw_spin(text, smallint)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.board_of(uuid)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.current_spin_of(uuid, smallint)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.options_of(text, smallint, boolean)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.lock_playing_run(uuid, uuid)
  from public, anon, authenticated;

revoke all on function qb_season_builder.state(uuid)        from public, anon;
revoke all on function qb_season_builder.start(uuid, text)  from public, anon;

grant execute on function qb_season_builder.state(uuid)       to authenticated;
grant execute on function qb_season_builder.start(uuid, text) to authenticated;
