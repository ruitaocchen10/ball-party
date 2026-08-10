-- The write API for runs and matches. See docs/architecture/architecture.md.
--
--   lobby        the room — people, code, durable
--     └── run    one sitting of one mode — arcade or party
--           └── match    one playthrough of one game
--
-- 0003 created these tables, gave them SELECT policies and put them in the
-- Realtime publication, and deliberately created no way to write to them. This
-- is that way. It follows 0005: `security definer` functions in `public`,
-- identity from auth.uid() and never from an argument, no INSERT/UPDATE/DELETE
-- policies on any table.
--
-- Two directions, deliberately asymmetric. Starting a run is a public RPC — a
-- host asks for it. Finishing a match is NOT: a public "here are the scores"
-- endpoint would be a forgeable result, which is the one thing
-- server-authoritative rules exist to prevent. A game closes its own match by
-- calling private.finish_match from inside the transaction that resolved its
-- last move.
--
-- This layer knows nothing about any specific game beyond its name. It does not
-- call any game's setup; it does not know they exist.
--
-- NOTE on drift: several comments in 0003 and 0005 say mutations go through an
-- Edge Function. Lobbies shipped as RPCs and architecture.md has been amended
-- to match. Applied migrations are append-only here, so those comments are
-- knowingly left alone rather than edited.

-- pgTAP, for the SQL tests in supabase/tests/. The first SQL test infrastructure
-- in the project — issue #1 established a Python stdlib runner for the pool
-- build and explicitly established nothing about the rest.
create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- starting one --

-- Returns the first match so the caller can go straight into the game's own
-- setup RPC with an id in hand.
--
-- The match is created in `setup`, not `playing`. The game moves it. That
-- leaves a real seam — these are two transactions, so a client can start a run
-- and vanish before dealing — and it is accepted, because the alternative is
-- this function dispatching into game-specific setup, which is exactly the
-- dependency the module rule in architecture.md forbids. A match stuck in
-- `setup` is swept by the janitor.
create function public.start_run(p_lobby_id uuid, p_mode public.run_mode, p_game text)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_lobby public.lobbies;
  v_count int;
  v_run   public.runs;
  v_match public.matches;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- Everything below is decided under this lock, so two people tapping start
  -- cannot both get through the checks.
  select * into v_lobby from public.lobbies where id = p_lobby_id for update;
  if not found then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  if v_lobby.closed_at is not null then
    raise exception 'lobby_closed' using errcode = 'P0001';
  end if;

  if v_lobby.host_id <> v_user then
    raise exception 'not_host' using errcode = '42501';
  end if;

  -- A host who left and had the room migrate away from them is not special.
  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and user_id = v_user and left_at is null
  ) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  select count(*) into v_count
    from public.lobby_members
   where lobby_id = p_lobby_id and left_at is null;

  -- The physical capacity of a lobby, and nothing else. Per-game minimums are
  -- the game's business: the auction's dealer refuses what it cannot deal. The
  -- platform must not learn what any particular game needs.
  if v_count < 2 or v_count > 4 then
    raise exception 'bad_player_count' using errcode = 'P0001';
  end if;

  -- The enum still carries 'party'; this function does not yet honour it.
  -- Party needs the point mapping that docs/games/auction_team_builder.md
  -- still lists as an open question. Arcade is the degenerate one-match case.
  if p_mode <> 'arcade'::public.run_mode then
    raise exception 'mode_not_supported' using errcode = 'P0001';
  end if;

  -- runs_one_active is what actually adjudicates a concurrent start. Checking
  -- first and inserting second would be a race; the index cannot be raced.
  begin
    insert into public.runs (lobby_id, mode)
    values (p_lobby_id, p_mode)
    returning * into v_run;
  exception when unique_violation then
    raise exception 'run_already_active' using errcode = 'P0001';
  end;

  -- Roster B: the snapshot. Seats are randomised rather than ordered by
  -- joined_at, because seat order drives the auction's opening-bid rotation
  -- and arrival order would mean the host opens the first lot of every game
  -- forever.
  --
  -- random() in the subquery target list is what pins the shuffle: a volatile
  -- function there stops the planner pulling the subquery up, so the window
  -- below orders by one fixed draw per row.
  insert into public.run_participants (run_id, user_id, seat)
  select v_run.id, s.user_id, (row_number() over (order by s.ord) - 1)::smallint
    from (
      select user_id, random() as ord
        from public.lobby_members
       where lobby_id = p_lobby_id and left_at is null
    ) s;

  insert into public.matches (run_id, game, seq, status)
  values (v_run.id, p_game, 1, 'setup'::public.match_status)
  returning * into v_match;

  return v_match;
end;
$$;

-- ------------------------------------------------------------ finishing one --

-- The seam where a game hands its result back to the platform.
--
-- p_scores is {"<user_id>": <raw score>}. Placement is derived here rather than
-- passed in, so no game gets to invent its own ranking: standard competition
-- ranking, ties sharing the better rank and the next placement skipping — what
-- scoreboards do and what people expect.
--
-- Not granted to anyone and unreachable from PostgREST, like everything in
-- `private`. A game calls it from inside its own transaction.
create function private.finish_match(p_match_id uuid, p_scores jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches;
begin
  select * into v_match from public.matches where id = p_match_id;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  insert into public.match_players (match_id, run_id, user_id, raw_score, placement)
  select p_match_id,
         v_match.run_id,
         s.user_id,
         s.raw_score,
         (rank() over (order by s.raw_score desc))::smallint
    from (
      select key::uuid as user_id, value::numeric as raw_score
        from jsonb_each_text(p_scores)
    ) s
  on conflict (match_id, user_id) do update
    set raw_score = excluded.raw_score,
        placement = excluded.placement;

  update public.matches
     set status = 'complete'::public.match_status,
         ended_at = now()
   where id = p_match_id;

  -- An arcade run is one match, so finishing the match finishes the run.
  -- Party's multi-match loop is not built; when it is, this is where it
  -- decides whether to deal another match instead.
  update public.runs
     set status = 'finished'::public.run_status,
         ended_at = now()
   where id = v_match.run_id
     and mode = 'arcade'::public.run_mode
     and status = 'active'::public.run_status;
end;
$$;

-- A match that will never finish. Called by the janitor and by lobby closure.
-- Separate from finish_match because there are no scores to write: nothing was
-- resolved, so nothing is recorded.
create function private.abandon_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.matches
     set status = 'abandoned'::public.match_status,
         ended_at = now()
   where id = p_match_id
     and status in ('setup'::public.match_status, 'playing'::public.match_status);
end;
$$;

-- Closing a room already abandons the run inside it (0005, amended in 0006) but
-- left its matches sitting `playing` forever. They go down with the room.
create or replace function private.close_lobby_internal(p_lobby_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.lobbies
     set closed_at = now()
   where id = p_lobby_id and closed_at is null;

  update public.matches m
     set status = 'abandoned'::public.match_status,
         ended_at = now()
    from public.runs r
   where m.run_id = r.id
     and r.lobby_id = p_lobby_id
     and m.status in ('setup'::public.match_status, 'playing'::public.match_status);

  update public.runs
     set status = 'abandoned'::public.run_status,
         ended_at = now()
   where lobby_id = p_lobby_id
     and status = 'active'::public.run_status;
end;
$$;

-- ----------------------------------------------------------------- privileges --
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. Take it back, then hand
-- out only what a signed-in player is allowed to ask for.

revoke all on function private.finish_match(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.abandon_match(uuid)       from public, anon, authenticated;

revoke all on function public.start_run(uuid, public.run_mode, text) from public, anon;
grant execute on function public.start_run(uuid, public.run_mode, text) to authenticated;
