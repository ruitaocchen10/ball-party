-- Higher or Lower: its schemas, its board, and the dealer that fills it.
--
-- The rules and the reasoning behind them are in issue #22.
-- docs/games/higher_or_lower.md is still empty; it gets written up when the
-- band schedule below is tuned against real ladders (#30).
--
-- THIS SLICE IS THE LADDER AND NOTHING ELSE. A dealt match holds the seed
-- anchor with its points showing and twelve challengers with theirs hidden.
-- The clock (#25), calling (#26) and the ending (#28) write into these tables
-- rather than replacing them.
--
-- TWO THINGS ARE LOAD-BEARING HERE.
--
-- The first is the two-table split, copied from the auction's 0010 for exactly
-- the reason that file gives: Realtime replicates whole rows, RLS decides who
-- receives a change rather than which columns it carries, and a column-level
-- GRANT does not filter a replication payload either. So an unrevealed card's
-- points do not live on the client-readable row at all. They live in
-- higher_or_lower_private.answers, which has no REST endpoint and is in no
-- publication, and revealing a question is the act of copying one number
-- across. The card's quantile gets the same treatment and for a stronger
-- reason: it is not just this card's answer, it is its rank in the whole deck.
--
-- The second is the band schedule. Every challenger is drawn at a controlled
-- quantile distance from the current anchor, and that distance tightens as the
-- ladder climbs. It is one function, deliberately, so difficulty is retuned
-- (#30) by dealing sample ladders and reading them rather than by touching
-- game logic. It asymptotes to a floor rather than tightening without bound,
-- because solo (push two) runs an endless ladder and will call it with indices
-- past twelve; the floor is what stops a long run ending on a coin flip.

-- ------------------------------------------------------------------ schemas --
--
-- The pattern 0029 established for the auction, followed rather than reinvented:
--
--   higher_or_lower          the write API a client may call. Exposed via
--                            PostgREST, so it holds nothing not meant to be
--                            reachable.
--   higher_or_lower_private  the rules engine. Not in the exposed schema list
--                            and no usage granted to anon or authenticated, so
--                            it is unreachable rather than merely unrouted.
--
-- The names are `matches.game` verbatim, so a durable match record needs no
-- translation to find the schema that owns it.
--
-- Exposing the public one also takes an entry in `[api] schemas` in
-- config.toml AND the hosted project's exposed-schema dashboard setting, which
-- is state no migration can carry. See supabase/README.md.

create schema if not exists higher_or_lower;
create schema if not exists higher_or_lower_private;

revoke all on schema higher_or_lower_private from public, anon, authenticated;

revoke all on schema higher_or_lower from public;
grant usage on schema higher_or_lower to anon, authenticated, service_role;

-- ------------------------------------------------------------------- tables --

-- The match's format, resolved at deal time and never re-derived.
--
-- Every one of these is a snapshot of a decision rather than a pointer at the
-- current default, for the reason the auction records its preset and purse: a
-- board dealt today has to stay readable after the defaults are retuned, and a
-- finished ladder that silently re-reads a new question count is a lie about
-- what was played.
create table public.higher_or_lower_matches (
  match_id         uuid     primary key references public.matches (id) on delete cascade,
  question_count   smallint not null check (question_count > 0),
  -- Reserved for sudden death (#28). Dealt now because they continue the same
  -- anchor chain under the same band — dealing them later would mean either
  -- re-deriving the chain or breaking it.
  spare_count      smallint not null check (spare_count >= 0),
  current_question smallint not null default 1 check (current_question > 0),
  scoring_mode     text     not null check (scoring_mode in ('season_total', 'weekly')),
  season_from      smallint not null check (season_from >= 2010),
  season_to        smallint not null check (season_to >= 2010),

  constraint higher_or_lower_matches_season_ordered check (season_from <= season_to)
);

-- The ladder. One row per card, in the order they are played.
--
-- Ordinal 0 is the seed anchor: it is dealt face up, because a player needs one
-- concrete number to price the first hidden card against. Ordinals 1..12 are
-- the questions — question k compares card k against card k-1 — and 13..17 are
-- the spares. So a card is both a challenger and, once it reveals, the anchor
-- for the next question, which is why there is one table rather than a pair.
--
-- `points` is null until this card's question reveals. `tier` and `pos_rank`
-- exist in the pool and are deliberately not copied here: either would place
-- the card in the distribution, which is the entire thing being withheld.
create table public.higher_or_lower_cards (
  match_id     uuid     not null references public.matches (id) on delete cascade,
  ordinal      smallint not null check (ordinal >= 0),

  -- What the card shows. player_id crosses over as the distinctness guard for
  -- the deal, and as the join back to the pool a test needs.
  player_id    text     not null,
  display_name text     not null,
  position     text     not null check (position in ('QB','RB','WR','TE')),
  season       smallint not null,
  team         text     not null,
  -- Weekly-only recall cues. Null in season-total mode, where a card is a whole
  -- season and has no honest week or opponent. Weekly mode is #29.
  week         smallint,
  opponent     text,
  headshot_url text,

  -- The reveal. Null until this card's question ends; the anchor is dealt
  -- already revealed.
  points       numeric(5,1),
  revealed_at  timestamptz,

  primary key (match_id, ordinal),

  -- The two halves of a reveal move together or the UI has to guess which one
  -- to believe.
  constraint higher_or_lower_cards_reveal_complete
    check ((points is null) = (revealed_at is null))
);

-- Who is playing. Seats are copied from run_participants rather than shuffled
-- again: the platform froze the order at run start and a game that reshuffles
-- it is inventing a second answer to a question already settled.
--
-- Streaks, correct counts and presence land here in #26 and #27.
create table public.higher_or_lower_players (
  match_id uuid     not null references public.matches (id) on delete cascade,
  user_id  uuid     not null references public.profiles (id),
  seat     smallint not null,

  primary key (match_id, user_id),
  unique (match_id, seat)
);

-- The answers. Same treatment as private.player_weeks and
-- private.auction_answers: no endpoint, no privileges, RLS on with no policies,
-- never in a publication. Belt and braces behind an absence of endpoint — none
-- of these should be the only thing between a player and the answers.
--
-- The quantile rides along with the points because it is the same secret in a
-- more useful form. It is also what the band assertions in the test suite read,
-- which is the honest reason it is stored rather than recomputed.
create table higher_or_lower_private.answers (
  match_id uuid             not null,
  ordinal  smallint         not null,
  points   numeric(5,1)     not null,
  quantile double precision not null,

  primary key (match_id, ordinal)
);

revoke all on table higher_or_lower_private.answers from public, anon, authenticated;
alter table higher_or_lower_private.answers enable row level security;

-- The seed a board was dealt from, kept where the answers are.
--
-- It is reproducibility for a maintainer, and it is private for exactly the
-- reason the points are: the dealer is in this file, the band schedule is in
-- this file and the source data is public, so a seed handed to a client is an
-- answer key with extra steps. Putting it on higher_or_lower_matches would also
-- replicate it over Realtime, which is the leak the split above exists to stop.
create table higher_or_lower_private.boards (
  match_id uuid        primary key references public.matches (id) on delete cascade,
  seed     double precision not null,
  dealt_at timestamptz not null default now()
);

revoke all on table higher_or_lower_private.boards from public, anon, authenticated;
alter table higher_or_lower_private.boards enable row level security;

-- ------------------------------------------------------------ the band --

-- One function, mapping a question index to the minimum and maximum quantile
-- distance the next card may sit at.
--
--   question 1   0.200 - 0.350 of the deck between the two cards
--   question 12  0.047 - 0.111
--   question ∞   0.040 - 0.100
--
-- Exponential decay onto a floor rather than a straight line down, so that
-- solo's endless ladder has something to converge on. A linear schedule
-- extended past twelve reaches zero and then goes negative, and a question with
-- zero distance between the cards is a coin flip with extra steps.
--
-- The minimum distance is also what makes exact ties structurally impossible,
-- so no part of this game has a per-question tie rule: quantiles come from
-- percent_rank, which gives equal points equal rank, so a strictly positive
-- distance is a guarantee the two cards score differently. The dealer keeps
-- that guarantee even when it widens the band — see the strict comparison in
-- the candidate query.
--
-- The values are starting numbers, to be tuned in #30 by dealing sample ladders
-- and reading them rather than by argument.
create function higher_or_lower_private.band(
  p_question_index int,
  out band_min double precision,
  out band_max double precision
)
language sql
immutable
set search_path = ''
as $$
  -- Clamped at both ends: below 1 because there is no question zero to ask
  -- about, and above 200 to keep pow() away from underflow. 0.75^199 is already
  -- 1e-25, so every index past it is the floor to far more precision than a
  -- deck of a few thousand cards can express.
  select 0.04::double precision + 0.16::double precision
           * power(0.75::double precision, least(greatest(p_question_index, 1), 200) - 1),
         0.10::double precision + 0.25::double precision
           * power(0.75::double precision, least(greatest(p_question_index, 1), 200) - 1);
$$;

-- --------------------------------------------------------------- the era --

-- Read from the pool, never written down. 0007 gave player_weeks.season a lower
-- bound and no upper one so a finished season could arrive as a migration; a
-- year hardcoded above the data would be the thing unable to reach the new rows.
-- player_seasons is derived from player_weeks, so one query answers for both.
create function higher_or_lower_private.season_bounds(
  out season_min smallint,
  out season_max smallint
)
language sql
stable
security definer
set search_path = ''
as $$ select min(season)::smallint, max(season)::smallint from private.player_weeks $$;

-- Resolve-and-refuse, in the shape 0030 established: the caller's nulls become
-- the full era here rather than in a table default, so a later change to the
-- pool cannot reach back and alter what an old match was dealt from, and
-- anything invalid raises rather than being clamped to the nearest legal value.
--
-- Unlike the auction there is no minimum span. The auction needs one because it
-- draws a fixed quota of star-tier players per position and a single season has
-- only five of each; this game draws by quantile distance, which normalises to
-- whatever deck is in play, so one season is a legitimate choice.
create function higher_or_lower_private.resolve_season_range(
  p_season_from smallint,
  p_season_to smallint,
  out season_from smallint,
  out season_to smallint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_min smallint; v_max smallint;
begin
  select b.season_min, b.season_max into v_min, v_max
    from higher_or_lower_private.season_bounds() b;

  season_from := coalesce(p_season_from, v_min);
  season_to   := coalesce(p_season_to, v_max);

  if season_from > season_to then
    raise exception 'invalid_season_range' using errcode = 'P0001';
  end if;
  if season_from < v_min or season_to > v_max then
    raise exception 'season_out_of_range' using errcode = 'P0001';
  end if;
end;
$$;

-- ------------------------------------------------------------- the deal --

-- Draws the whole ladder in one transaction, because a half-dealt board is a
-- broken match.
--
--   1 seed anchor    drawn from the middle of the distribution
--  12 questions      each at a band-controlled distance from the one before
--   5 spares         the same chain, continued, for sudden death
--
-- The seed is an argument so tests can pin a board and so a ladder somebody
-- complains about can be dealt again and examined. It is deliberately NOT an
-- argument of the public entry point: a client that chose the seed could replay
-- this against a copy of the public source data and know every answer before
-- the first question opened.
create function higher_or_lower_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null,
  p_scoring_mode text default 'season_total',
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seed           double precision := coalesce(p_seed, random());
  -- Fixed, and recorded on the match row. A host match-length picker is out of
  -- scope for push one; five spares is what sudden death's five-round cap can
  -- consume.
  v_question_count constant smallint := 12;
  v_spare_count    constant smallint := 5;
  v_from           smallint;
  v_to             smallint;
  v_n              int;
  v_i              int;
  v_band_min       double precision;
  v_band_max       double precision;
  v_min            double precision;
  v_max            double precision;
  v_widen          int;
  v_above          boolean;
  v_below          boolean;
  v_take_above     boolean;
  v_anchor         double precision;
  v_card           record;
  v_used           text[] := '{}';
begin
  if p_scoring_mode = 'weekly' then
    -- The column and the card fields are here; the deck is not. Weekly is #29.
    raise exception 'scoring_mode_not_supported' using errcode = 'P0001';
  elsif p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;

  -- Before the first insert, so a refused range costs nothing.
  select r.season_from, r.season_to into v_from, v_to
    from higher_or_lower_private.resolve_season_range(p_season_from, p_season_to) r;

  -- Everything below draws from this. A parallel plan would divide the work
  -- across workers with their own PRNG state and the seed would stop meaning
  -- anything, so parallelism is off for the duration.
  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  insert into public.higher_or_lower_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  select count(*) into v_n from public.higher_or_lower_players where match_id = p_match_id;

  -- The platform already refused a one-person lobby. This is the game's own
  -- floor, which belongs here rather than there: the platform must not learn
  -- what any particular game needs.
  if v_n < 2 then
    raise exception 'too_few_players' using errcode = 'P0001';
  end if;

  -- THE DECK, and the ranking that makes the band mean anything.
  --
  -- percent_rank over points across exactly the rows this mode and era select,
  -- so "0.2 of the deck apart" means the same thing in a 2010-2025 board and in
  -- a single-season one. It is computed per deal rather than stored on the pool
  -- for that reason: a stored rank would be a rank in some other deck.
  --
  -- percent_rank rather than row_number is also what makes equal points
  -- impossible to deal consecutively: tied rows share a rank, so a strictly
  -- positive distance is a guarantee the points differ.
  --
  -- A temp table because the deck is read three times per card — twice to ask
  -- which directions have candidates, once to draw — and is small, a few
  -- thousand rows for a full-era season deck. Dropped first because a test
  -- transaction deals several boards and `on commit drop` only fires at commit;
  -- the plans below are re-planned against the new table each time, which is
  -- what makes dropping and recreating it inside a function safe.
  drop table if exists pg_temp.higher_or_lower_deck;
  create temporary table higher_or_lower_deck on commit drop as
  select s.player_id,
         s.display_name,
         s.position,
         s.season,
         s.team,
         null::smallint as week,
         null::text     as opponent,
         s.points,
         percent_rank() over (order by s.points) as quantile,
         -- Left join in spirit, as in 0013: a player the headshot table has not
         -- caught up with still deals a perfectly good card, with an empty band.
         h.headshot_url
    from private.player_seasons s
    left join private.player_headshots h on h.player_id = s.player_id
   where s.season between v_from and v_to;

  for v_i in 0 .. (v_question_count + v_spare_count) loop
    if v_i = 0 then
      -- THE SEED ANCHOR, from the middle of the distribution rather than
      -- uniformly. A uniform draw puts roughly a third of matches on an anchor
      -- with nothing at question one's distance on one side, which would make
      -- the widening backstop the mechanism rather than the backstop. The
      -- window is what question one's band needs: at 0.35 there is room for a
      -- card 0.20-0.35 below, and at 0.65 room for one above.
      select d.* into v_card
        from pg_temp.higher_or_lower_deck d
       where d.quantile between 0.35 and 0.65
       order by random()
       limit 1;

      -- Cannot happen with the current pool at any era window, so if it fires
      -- something is wrong with the pool rather than with the request, and a
      -- short board would hide it.
      if not found then
        raise exception 'pool_exhausted' using errcode = 'P0001';
      end if;
    else
      select b.band_min, b.band_max into v_band_min, v_band_max
        from higher_or_lower_private.band(v_i) b;

      -- Widening is a backstop for a narrow era window, not the mechanism. It
      -- is a fixed step and it is deterministic, so a widened board is still
      -- exactly reproducible from its seed.
      v_widen := 0;
      loop
        v_min := greatest(v_band_min - v_widen * 0.05::double precision, 0::double precision);
        v_max := least(v_band_max + v_widen * 0.05::double precision, 1::double precision);

        -- Above and below are counted separately, and the comparison is strict
        -- rather than `abs(...) >= v_min`. That is what keeps equal-points
        -- cards out of the candidate set even after widening drags v_min to
        -- zero — the one place the no-ties guarantee could otherwise be lost.
        select exists (
          select 1 from pg_temp.higher_or_lower_deck d
           where d.quantile > v_anchor
             and d.quantile - v_anchor between v_min and v_max
             and not (d.player_id = any (v_used))
        ) into v_above;

        select exists (
          select 1 from pg_temp.higher_or_lower_deck d
           where d.quantile < v_anchor
             and v_anchor - d.quantile between v_min and v_max
             and not (d.player_id = any (v_used))
        ) into v_below;

        exit when v_above or v_below;

        v_widen := v_widen + 1;
        if v_widen > 20 then
          raise exception 'pool_exhausted' using errcode = 'P0001';
        end if;
      end loop;

      -- When both sides are populated the direction is a coin flip, so the
      -- correct answer is not biased upward or downward and a player cannot
      -- win by always calling one way. When only one is, it is not a choice.
      v_take_above := case when v_above and v_below then random() < 0.5 else v_above end;

      select d.* into v_card
        from pg_temp.higher_or_lower_deck d
       where not (d.player_id = any (v_used))
         and case
               when v_take_above
                 then d.quantile > v_anchor and d.quantile - v_anchor between v_min and v_max
               else d.quantile < v_anchor and v_anchor - d.quantile between v_min and v_max
             end
       order by random()
       limit 1;

      if not found then
        raise exception 'pool_exhausted' using errcode = 'P0001';
      end if;
    end if;

    insert into public.higher_or_lower_cards (
      match_id, ordinal, player_id, display_name, position,
      season, team, week, opponent, headshot_url, points, revealed_at
    )
    values (
      p_match_id, v_i, v_card.player_id, v_card.display_name, v_card.position,
      v_card.season, v_card.team, v_card.week, v_card.opponent, v_card.headshot_url,
      -- The anchor is the one card dealt face up. Everything else reveals when
      -- its question ends (#25).
      case when v_i = 0 then v_card.points end,
      case when v_i = 0 then now() end
    );

    insert into higher_or_lower_private.answers (match_id, ordinal, points, quantile)
    values (p_match_id, v_i, v_card.points, v_card.quantile);

    -- Distinctness is by player, not by card, so a ladder never asks anyone to
    -- compare two seasons of the same person. It holds in weekly mode for free.
    v_used   := v_used || v_card.player_id;
    v_anchor := v_card.quantile;
  end loop;

  insert into public.higher_or_lower_matches (
    match_id, question_count, spare_count, current_question,
    scoring_mode, season_from, season_to
  )
  values (
    p_match_id, v_question_count, v_spare_count, 1,
    p_scoring_mode, v_from, v_to
  );

  insert into higher_or_lower_private.boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

-- --------------------------------------------------------- the entry point --

-- What a client is told about the board. A projection, not the table: adding a
-- column to higher_or_lower_matches must never be silently also a decision to
-- publish it. The phase and its deadline join this in #25.
--
-- A named type rather than bare OUT parameters, so the generated client types
-- name these fields instead of falling back to an untyped record — the same
-- reason auction.turn is a type.
create type higher_or_lower.board as (
  match_id         uuid,
  question_count   smallint,
  spare_count      smallint,
  current_question smallint,
  scoring_mode     text,
  season_from      smallint,
  season_to        smallint
);

create function higher_or_lower_private.board_of(p_match_id uuid)
returns higher_or_lower.board
language sql
stable
security definer
set search_path = ''
as $$
  select (m.match_id, m.question_count, m.spare_count, m.current_question,
          m.scoring_mode, m.season_from, m.season_to)::higher_or_lower.board
    from public.higher_or_lower_matches m
   where m.match_id = p_match_id;
$$;

-- The thin public entry point. Takes no seed, on purpose — see the dealer.
--
-- The era defaults to the whole pool and still goes through the resolver, so
-- "omitted" is a validated choice rather than an unchecked path. The host's
-- picker for both of these is #29; what it will send is already accepted here.
create function higher_or_lower.start(
  p_match_id uuid,
  p_scoring_mode text default 'season_total',
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns higher_or_lower.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- Refused at the boundary as well as in the dealer, so a direct RPC caller is
  -- turned away before the match row is locked rather than after.
  if p_scoring_mode = 'weekly' then
    raise exception 'scoring_mode_not_supported' using errcode = 'P0001';
  elsif p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  perform higher_or_lower_private.resolve_season_range(p_season_from, p_season_to);

  -- The lock is what makes "deal twice" impossible rather than unlikely.
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  if v_match.game <> 'higher_or_lower' then
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

  perform higher_or_lower_private.deal_board(
    p_match_id, null, p_scoring_mode, p_season_from, p_season_to
  );

  -- The board exists, so the match is playing. The phase machine that carries
  -- it from here is #25; until then it sits on question one.
  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  return higher_or_lower_private.board_of(p_match_id);
end;
$$;

-- ---------------------------------------------------------------------- RLS --

alter table public.higher_or_lower_matches enable row level security;
alter table public.higher_or_lower_cards   enable row level security;
alter table public.higher_or_lower_players enable row level security;

-- private.is_match_member is the platform's membership helper (0010), reached
-- from a policy rather than from this game's code. The module rule the
-- architecture doc describes runs the other way: a game may not reach into
-- lobbies, and this does not — it asks a question the platform answers.
create policy higher_or_lower_matches_select_member on public.higher_or_lower_matches
  for select to authenticated using (private.is_match_member(match_id));

create policy higher_or_lower_cards_select_member on public.higher_or_lower_cards
  for select to authenticated using (private.is_match_member(match_id));

create policy higher_or_lower_players_select_member on public.higher_or_lower_players
  for select to authenticated using (private.is_match_member(match_id));

-- No INSERT/UPDATE/DELETE policies anywhere, consistent with every table since
-- 0003. Every write goes through a definer function, which is owned by postgres
-- and bypasses both the grant and the policy.

-- Granted explicitly rather than left to whatever default privileges a given
-- environment happens to carry — the hosted project grants public tables to
-- anon and authenticated by default and a local CLI stack no longer does. RLS,
-- not this grant, is what decides which rows come back.
grant select on public.higher_or_lower_matches to authenticated;
grant select on public.higher_or_lower_cards   to authenticated;
grant select on public.higher_or_lower_players to authenticated;

-- ----------------------------------------------------------------- realtime --
-- The three client-readable tables in, and neither private table. RLS applies
-- to replication, so these fan out only to players in the match — and an
-- unrevealed card's payload has no points on it to fan out.

alter publication supabase_realtime add table public.higher_or_lower_matches;
alter publication supabase_realtime add table public.higher_or_lower_cards;
alter publication supabase_realtime add table public.higher_or_lower_players;

-- ---------------------------------------------------------------- privileges --
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. Take it back, then hand
-- out only what a signed-in player is allowed to ask for.

revoke all on function higher_or_lower_private.band(int)                             from public, anon, authenticated;
revoke all on function higher_or_lower_private.season_bounds()                       from public, anon, authenticated;
revoke all on function higher_or_lower_private.resolve_season_range(smallint, smallint) from public, anon, authenticated;
revoke all on function higher_or_lower_private.board_of(uuid)                        from public, anon, authenticated;
revoke all on function higher_or_lower_private.deal_board(uuid, double precision, text, smallint, smallint)
  from public, anon, authenticated;

revoke all on function higher_or_lower.start(uuid, text, smallint, smallint) from public, anon;
grant execute on function higher_or_lower.start(uuid, text, smallint, smallint) to authenticated;
