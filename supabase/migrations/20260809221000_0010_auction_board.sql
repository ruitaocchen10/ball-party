-- The auction's board: lots, players, budgets, and the dealer that fills them.
-- Game rules in docs/games/auction_team_builder.md.
--
-- THE LOAD-BEARING DECISION IS THE TWO-TABLE SPLIT.
--
-- 0007 put the player pool in `private` so the browser cannot read the answers.
-- Lots are different: the browser MUST read them, because the card on screen is
-- a lot row. So the hiding can no longer be "this table is unreachable" — it
-- has to be "this row does not contain the answer yet."
--
-- A hidden column is not enough. Realtime replicates whole rows. RLS decides
-- whether a subscriber receives a change, not which columns it contains, and
-- column-level GRANTs do not filter the replication payload either. A `points`
-- column sitting null-until-revealed on a replicated row would leak the moment
-- anything wrote it — through the WebSocket, not through the UI. A player would
-- not have to be clever; they would have to open the network tab.
--
-- So the answer does not live on the lot row at all until the moment it is
-- public. It lives in private.auction_answers, which has no REST endpoint and
-- is in no publication. Resolving a lot copies one number across, and that copy
-- IS the reveal. See 0011.

-- ------------------------------------------------------------------ the lot --

create table public.auction_lots (
  match_id     uuid     not null references public.matches (id) on delete cascade,
  seq          smallint not null check (seq > 0),

  -- What the card shows. These six are the only columns copied out of the pool.
  --
  -- `tier` and `pos_rank` are in the pool and are NOT copied, deliberately.
  -- Knowing a card is `star` tells a bidder the answer's neighbourhood before
  -- anyone has bid, which is exactly the hint this game is built to withhold.
  -- player_id crosses over only as the distinctness guard for the deal.
  player_id    text     not null,
  display_name text     not null,
  position     text     not null check (position in ('QB','RB','WR','TE')),
  season       smallint not null,
  week         smallint not null,
  team         text     not null,
  opponent     text     not null,
  is_flex      boolean  not null,

  -- The outcome. All null until this lot resolves.
  winner_id    uuid     references public.profiles (id),
  price        int      check (price >= 0),
  slot         text     check (slot in ('QB','RB','WR','TE','FLEX')),
  points       numeric(5,1),
  resolved_at  timestamptz,

  primary key (match_id, seq)
);

create index auction_lots_by_winner on public.auction_lots (match_id, winner_id)
  where winner_id is not null;

-- The answers. Same treatment as private.player_weeks: no endpoint, no
-- privileges, RLS on with no policies, never in a publication. Belt and braces
-- behind an absence of endpoint — none of these should be the only thing
-- standing between a player and the answers.
create table private.auction_answers (
  match_id uuid         not null,
  seq      smallint     not null,
  points   numeric(5,1) not null,
  primary key (match_id, seq)
);

revoke all on table private.auction_answers from public, anon, authenticated;
alter table private.auction_answers enable row level security;

-- --------------------------------------------------------------- the match --

create table public.auction_matches (
  match_id      uuid primary key references public.matches (id) on delete cascade,
  lot_count     smallint         not null check (lot_count > 0),
  current_lot   smallint         not null default 1,
  -- The seat on the clock. Null once the board is played out.
  turn_seat     smallint,
  -- The right to open at $0, which rotates one seat per lot.
  opener_seat   smallint         not null default 0,
  turn_deadline timestamptz
);

-- Turn state lives here because the game is turn-based by design — the rules
-- chose that specifically so only one player can act at any moment. One row to
-- lock is the whole concurrency story. See 0011.

-- The seed a board was dealt from, kept where the answers are.
--
-- It is reproducibility for a maintainer, and it belongs in `private` for
-- exactly the reason the points do: the dealer is in this file, the tier bands
-- are in the repository and the source data is public, so a seed handed to a
-- client is an answer key with extra steps. Storing it on auction_matches would
-- also replicate it over Realtime, which is the same leak the split at the top
-- of this file exists to prevent.
create table private.auction_boards (
  match_id uuid        primary key references public.matches (id) on delete cascade,
  seed     double precision not null,
  dealt_at timestamptz not null default now()
);

revoke all on table private.auction_boards from public, anon, authenticated;
alter table private.auction_boards enable row level security;

-- What a client is told about the state of the board. It is a projection, not
-- the table: it exists so that adding a column to auction_matches is never
-- silently also a decision to publish it.
--
-- server_now rides along so a client can offset its own clock rather than trust
-- it. The countdown is rendered from turn_deadline minus corrected local time;
-- a deadline the client owns is not a rule.
create type public.auction_turn as (
  match_id      uuid,
  lot_count     smallint,
  current_lot   smallint,
  turn_seat     smallint,
  opener_seat   smallint,
  turn_deadline timestamptz,
  server_now    timestamptz
);

create table public.auction_players (
  match_id uuid     not null references public.matches (id) on delete cascade,
  user_id  uuid     not null references public.profiles (id),
  -- Copied from run_participants, not re-derived. The platform froze turn
  -- order at run start; the auction inherits it rather than shuffling again.
  seat     smallint not null,
  budget   int      not null default 50 check (budget >= 0),
  primary key (match_id, user_id),
  unique (match_id, seat)
);

-- A player's roster is derived: `select slot from auction_lots where
-- match_id = ? and winner_id = ?`. A roster table would be a second copy of the
-- same fact and could drift from the lot rows that are the actual record of
-- what happened.

-- The action log. Written by 0011; created here so the schema reads in one
-- place. It is what the UI replays and what makes a disputed lot readable
-- afterwards.
create table public.auction_bids (
  match_id   uuid        not null,
  seq        smallint    not null,
  bid_seq    smallint    not null,
  user_id    uuid        not null references public.profiles (id),
  action     text        not null check (action in ('raise','pass')),
  -- The price after a raise. Null on a pass.
  price      int         check (price >= 0),
  by_timeout boolean     not null default false,
  created_at timestamptz not null default now(),
  primary key (match_id, seq, bid_seq),
  foreign key (match_id, seq) references public.auction_lots (match_id, seq) on delete cascade,
  constraint auction_bids_price_matches_action
    check ((action = 'raise') = (price is not null))
);

-- ------------------------------------------------------------------ the deal --

-- Draws the whole board in one transaction, because a half-dealt board is a
-- broken match.
--
--   4N base lots   N each of QB, RB, WR, TE
--    N flex lots   drawn from {RB, WR, TE}
--   5N total       at a full table, 20
--
-- The seed is an argument so tests can pin a board and so a weird board can be
-- looked at rather than retold. It is deliberately NOT an argument of the
-- public entry point: a client that chose the seed could replay this deal
-- against a copy of the source data and know every answer before bidding
-- opened. See start_auction.
create function private.deal_auction_board(p_match_id uuid, p_seed double precision default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seed  double precision := coalesce(p_seed, random());
  v_n     int;
  v_total int;
  v_star  int;
  v_solid int;
  v_deep  int;
  v_order text[];
  v_slots text[];
  v_tiers text[];
  v_used  text[] := '{}';
  v_row   private.player_weeks;
  v_i     int;
begin
  -- Everything below is drawn from this. A parallel plan would divide the work
  -- across workers with their own PRNG state and the seed would stop meaning
  -- anything, so parallelism is off for the duration.
  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  insert into public.auction_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  select count(*) into v_n from public.auction_players where match_id = p_match_id;

  -- The platform already refused a one-person lobby. This is the game-specific
  -- floor, which belongs here rather than there: the platform must not learn
  -- what any particular game needs.
  if v_n < 2 then
    raise exception 'too_few_players' using errcode = 'P0001';
  end if;

  v_total := 5 * v_n;

  -- The 7:8:5 tier ratio spread over 5N lots by largest remainder, ties to
  -- star. N=4 gives 7/8/5, N=3 gives 5/6/4, N=2 gives 4/4/2. Deterministic, so
  -- a seed fully determines a board.
  v_star  := (7 * v_total) / 20;
  v_solid := (8 * v_total) / 20;
  v_deep  := (5 * v_total) / 20;

  -- Whatever the floors dropped goes to the largest remainders first. The `ord`
  -- column is the tie-break, and star leading it is what "ties to star" means:
  -- at N=2 star and deep both sit on 10/20 and star takes the lot.
  select array_agg(t order by rem desc, ord)
    into v_order
    from (values
      ('star',  (7 * v_total) % 20, 1),
      ('solid', (8 * v_total) % 20, 2),
      ('deep',  (5 * v_total) % 20, 3)
    ) as remainders (t, rem, ord);

  for v_i in 1 .. (v_total - v_star - v_solid - v_deep) loop
    if v_order[v_i] = 'star' then
      v_star := v_star + 1;
    elsif v_order[v_i] = 'solid' then
      v_solid := v_solid + 1;
    else
      v_deep := v_deep + 1;
    end if;
  end loop;

  -- Base lots: N of each position, shuffled. Flex lots: N from {RB, WR, TE} in
  -- whatever proportion the shuffle produces — they are the leftover round by
  -- design, so no attempt is made to balance them.
  --
  -- seq is assigned from this order, so seq is play order and the flex lots are
  -- always the last N. The no-stranding argument depends on that and on the
  -- eligibility rule in 0011; neither works alone.
  select array_agg(pos order by random()) into v_slots
    from (
      select p as pos
        from unnest(array['QB','RB','WR','TE']) p,
             generate_series(1, v_n)
    ) base;

  v_slots := v_slots || (
    select array_agg((array['RB','WR','TE'])[1 + floor(random() * 3)::int])
      from generate_series(1, v_n)
  );

  -- The two constraints — position counts and tier counts — have to hold at
  -- once, and drawing players first and hoping the tiers land right does not
  -- work. So the tier tokens are shuffled onto the position slots, and then
  -- exactly one row is drawn per resulting (position, tier) pair.
  select array_agg(t order by random()) into v_tiers
    from (
      select 'star'  as t from generate_series(1, v_star)
      union all
      select 'solid'      from generate_series(1, v_solid)
      union all
      select 'deep'       from generate_series(1, v_deep)
    ) tokens;

  for v_i in 1 .. v_total loop
    -- Without replacement across the whole board rather than per pair. The same
    -- player in two different weeks is defensible and reads as a bug at the
    -- table.
    select pw.* into v_row
      from private.player_weeks pw
     where pw.position = v_slots[v_i]
       and pw.tier = v_tiers[v_i]
       and not (pw.player_id = any (v_used))
     order by random()
     limit 1;

    -- Fail the deal rather than deal a short board. This cannot happen with the
    -- current pool — the thinnest cell has thousands of rows — so if it fires,
    -- something is wrong with the pool rather than with the request, and a
    -- short board would hide it.
    if not found then
      raise exception 'pool_exhausted' using errcode = 'P0001';
    end if;

    v_used := v_used || v_row.player_id;

    insert into public.auction_lots (
      match_id, seq, player_id, display_name, position,
      season, week, team, opponent, is_flex
    )
    values (
      p_match_id, v_i, v_row.player_id, v_row.display_name, v_row.position,
      v_row.season, v_row.week, v_row.team, v_row.opponent, v_i > 4 * v_n
    );

    insert into private.auction_answers (match_id, seq, points)
    values (p_match_id, v_i, v_row.points);
  end loop;

  insert into public.auction_matches (match_id, lot_count, current_lot, opener_seat)
  values (p_match_id, v_total, 1, 0);

  insert into private.auction_boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

-- The thin public entry point. Takes no seed, on purpose — see above.
create function public.start_auction(p_match_id uuid)
returns public.auction_turn
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
  v_board public.auction_matches;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- The lock is what makes "deal twice" impossible rather than unlikely.
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  if v_match.game <> 'auction_team_builder' then
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

  perform private.deal_auction_board(p_match_id);

  -- The board is dealt, so the first lot is open and somebody is on the clock.
  -- 0011 replaces this with the opening that knows about eligibility.
  update public.auction_matches
     set turn_seat = opener_seat,
         turn_deadline = now() + interval '10 seconds'
   where match_id = p_match_id
  returning * into v_board;

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  return (
    v_board.match_id, v_board.lot_count, v_board.current_lot,
    v_board.turn_seat, v_board.opener_seat, v_board.turn_deadline, now()
  )::public.auction_turn;
end;
$$;

-- ---------------------------------------------------------------------- RLS --

-- match -> run -> lobby membership, in the same shape as private.is_run_member.
create function private.is_match_member(p_match_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.matches mt
    join public.runs r on r.id = mt.run_id
    join public.lobby_members lm on lm.lobby_id = r.lobby_id
    where mt.id = p_match_id
      and lm.user_id = auth.uid()
      and lm.left_at is null
  );
$$;

revoke all on function private.is_match_member(uuid) from public, anon;
grant execute on function private.is_match_member(uuid) to authenticated;

alter table public.auction_matches enable row level security;
alter table public.auction_players enable row level security;
alter table public.auction_lots    enable row level security;
alter table public.auction_bids    enable row level security;

create policy auction_matches_select_member on public.auction_matches
  for select to authenticated using (private.is_match_member(match_id));

create policy auction_players_select_member on public.auction_players
  for select to authenticated using (private.is_match_member(match_id));

create policy auction_lots_select_member on public.auction_lots
  for select to authenticated using (private.is_match_member(match_id));

create policy auction_bids_select_member on public.auction_bids
  for select to authenticated using (private.is_match_member(match_id));

-- No INSERT/UPDATE/DELETE policies anywhere, consistent with 0003 and 0005.
-- Every write goes through a definer function, which is owned by postgres and
-- bypasses both the grant and the policy.

-- Granted explicitly rather than left to whatever default privileges a given
-- environment happens to carry — the hosted project grants public tables to
-- anon and authenticated by default and a local CLI stack no longer does, and a
-- table the client cannot select from is a table the game cannot render. RLS,
-- not this grant, is what decides which rows come back.
grant select on public.auction_matches to authenticated;
grant select on public.auction_players to authenticated;
grant select on public.auction_lots    to authenticated;
grant select on public.auction_bids    to authenticated;

-- ----------------------------------------------------------------- realtime --
-- Four tables in, and private.auction_answers deliberately not. RLS applies to
-- replication, so these fan out only to players in the match.

alter publication supabase_realtime add table public.auction_matches;
alter publication supabase_realtime add table public.auction_players;
alter publication supabase_realtime add table public.auction_lots;
alter publication supabase_realtime add table public.auction_bids;

-- ---------------------------------------------------------------- privileges --

revoke all on function private.deal_auction_board(uuid, double precision)
  from public, anon, authenticated;

revoke all on function public.start_auction(uuid) from public, anon;
grant execute on function public.start_auction(uuid) to authenticated;
