-- Lobby / run / match structure. See docs/architecture/lobbies/lobbies.md.
--
--   lobby        the room — people, code, durable
--     └── run    one sitting of one mode — arcade or party
--           └── match    one playthrough of one game
--
-- The lobby has no mode. Mode is chosen per run, from inside the room.
--
-- NOTE: the RLS helper functions created here are moved to the `private`
-- schema in 0004. Read the two together.

-- ---------------------------------------------------------------- the room --

create table public.lobbies (
  id         uuid primary key default gen_random_uuid(),
  code       text not null check (code ~ '^[A-Z0-9]{5}$'),
  host_id    uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  closed_at  timestamptz
);

-- Codes are read aloud, so they are short, so they must be recycled. Scoping
-- uniqueness to open rooms is what makes a 5-character code sustainable.
create unique index lobbies_open_code on public.lobbies (code) where closed_at is null;

-- Roster A: who is in the room right now. Mutable.
-- A reconnect updates this row in place (left_at back to null) rather than
-- inserting a second one — hence the natural primary key.
create table public.lobby_members (
  lobby_id  uuid not null references public.lobbies (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  left_at   timestamptz,
  primary key (lobby_id, user_id)
);

create index lobby_members_by_user on public.lobby_members (user_id) where left_at is null;

-- The 4-player cap is not expressible here. It belongs in the join Edge
-- Function, taken under a row lock on the lobby, or two people racing the
-- last seat both get it.

-- --------------------------------------------------------------- the sitting --

create type public.run_mode   as enum ('arcade', 'party');
create type public.run_status as enum ('active', 'finished', 'abandoned');

create table public.runs (
  id           uuid not null primary key default gen_random_uuid(),
  lobby_id     uuid not null references public.lobbies (id) on delete cascade,
  mode         public.run_mode not null,
  status       public.run_status not null default 'active',
  target_score int,
  started_at   timestamptz not null default now(),
  ended_at     timestamptz,
  -- first-to-N is a party concept; arcade declares a winner and stops.
  constraint runs_target_is_party_only check (mode = 'party' or target_score is null)
);

-- A room does one thing at a time.
create unique index runs_one_active on public.runs (lobby_id) where status = 'active';
create index runs_by_lobby on public.runs (lobby_id);

-- Roster B: the snapshot. Written once at run start, never re-read from the
-- lobby. Deliberately has NO foreign key to lobby_members — leaving the room
-- must not be able to delete a player out of a run in progress. That is the
-- whole point of the two-roster split.
create table public.run_participants (
  run_id  uuid not null references public.runs (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  seat    smallint not null check (seat between 0 and 3),
  score   int not null default 0,
  primary key (run_id, user_id),
  -- Turn order is frozen here, not on lobby_members, so it cannot reshuffle
  -- mid-run when somebody walks out.
  unique (run_id, seat)
);

create index run_participants_by_user on public.run_participants (user_id);

-- ---------------------------------------------------------- the playthrough --

create type public.match_status as enum ('setup', 'playing', 'complete', 'abandoned');

create table public.matches (
  id         uuid not null primary key default gen_random_uuid(),
  run_id     uuid not null references public.runs (id) on delete cascade,
  game       text not null check (game in (
               'auction_team_builder',
               'cards_against_humanity',
               'higher_or_lower',
               'wavelength_2v2'
             )),
  seq        smallint not null check (seq > 0),
  status     public.match_status not null default 'setup',
  started_at timestamptz,
  ended_at   timestamptz,
  unique (run_id, seq)
);

create index matches_by_run on public.matches (run_id);

-- The seam between a game and the party scoreboard. Game-native state
-- (auction lots, wavelength rounds and their RLS-hidden targets) lives in
-- per-game tables keyed on match_id and stays out of this layer.
create table public.match_players (
  match_id       uuid not null references public.matches (id) on delete cascade,
  run_id         uuid not null,
  user_id        uuid not null,
  team           smallint,
  raw_score      numeric,
  placement      smallint check (placement between 1 and 4),
  points_awarded int,
  primary key (match_id, user_id),
  -- run_id is carried redundantly to buy this: you cannot appear in a match
  -- unless you were in that run's snapshot. A database guarantee rather than
  -- a rule an Edge Function has to remember.
  foreign key (run_id, user_id) references public.run_participants (run_id, user_id)
);

create index match_players_by_run on public.match_players (run_id, user_id);

-- ---------------------------------------------------------------------- RLS --

alter table public.lobbies          enable row level security;
alter table public.lobby_members    enable row level security;
alter table public.runs             enable row level security;
alter table public.run_participants enable row level security;
alter table public.matches          enable row level security;
alter table public.match_players    enable row level security;

-- A policy on lobby_members that subqueries lobby_members recurses forever.
-- security definer breaks the cycle by running the lookup outside RLS.
create or replace function public.is_lobby_member(p_lobby_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.lobby_members
    where lobby_id = p_lobby_id
      and user_id = auth.uid()
      and left_at is null
  );
$$;

create or replace function public.is_run_member(p_run_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.runs r
    join public.lobby_members m on m.lobby_id = r.lobby_id
    where r.id = p_run_id
      and m.user_id = auth.uid()
      and m.left_at is null
  );
$$;

-- Everything in the room is gated on CURRENT membership.
create policy lobbies_select_member on public.lobbies
  for select to authenticated using (public.is_lobby_member(id));

create policy lobby_members_select_member on public.lobby_members
  for select to authenticated using (public.is_lobby_member(lobby_id));

create policy runs_select_member on public.runs
  for select to authenticated using (public.is_lobby_member(lobby_id));

create policy run_participants_select_member on public.run_participants
  for select to authenticated using (public.is_run_member(run_id));

create policy matches_select_member on public.matches
  for select to authenticated using (public.is_run_member(run_id));

create policy match_players_select_member on public.match_players
  for select to authenticated using (public.is_run_member(run_id));

-- No lookup-by-code policy on purpose. Joining goes through an Edge Function
-- so a client cannot enumerate codes to find strangers' rooms.

-- No insert/update/delete policies anywhere in this migration, also on
-- purpose. Every mutation goes through an Edge Function on the service role.
-- No game rule is ever enforced client-side.

-- The promised second profiles policy. Note the asymmetry against the rules
-- above: this one does NOT filter on left_at. A player who leaves mid-party
-- stays a run participant and keeps their points, so the players still in the
-- room must be able to render that name in the standings.
create or replace function public.shares_lobby_with(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.lobby_members mine
    join public.lobby_members theirs on theirs.lobby_id = mine.lobby_id
    where mine.user_id = auth.uid()
      and theirs.user_id = p_user_id
  );
$$;

create policy profiles_select_co_player on public.profiles
  for select to authenticated
  using (
    public.shares_lobby_with(id)
    and (auth.jwt() ->> 'is_anonymous')::boolean is not true
  );

-- ----------------------------------------------------------------- realtime --
-- RLS applies to replication, so these fan out only to players who pass the
-- policies above.

alter publication supabase_realtime add table public.lobbies;
alter publication supabase_realtime add table public.lobby_members;
alter publication supabase_realtime add table public.runs;
alter publication supabase_realtime add table public.run_participants;
alter publication supabase_realtime add table public.matches;
alter publication supabase_realtime add table public.match_players;
