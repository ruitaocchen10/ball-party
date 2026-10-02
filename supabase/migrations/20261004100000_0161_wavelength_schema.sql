-- 2v2 Wavelength: its schema pair, tables, tunables, card deck, and the entry
-- points that deal a match. See docs/games/2v2_wavelength.md (the rules) and
-- docs/games/wavelength_implementation.md (the plan); this is issue #97, the
-- first slice of #96.
--
-- THIS SLICE IS THE FOUNDATION AND NOTHING ELSE. A dealt match exists and can
-- be read: its rounds, its cards, its hidden targets, its teams. There is no
-- clue writing, guessing, scoring or timer yet — those are #99 to #102.
--
-- Follows the pattern 0029 (auction), 0032 (Higher or Lower) and 0051
-- (Sabotage Draft) established:
--
--   wavelength          the write API a client may call. Exposed through
--                       PostgREST, so it holds nothing not meant to be
--                       reachable.
--   wavelength_private  the rules engine and the card deck. Not exposed, and
--                       no usage granted to anon or authenticated, so it is
--                       unreachable rather than merely unrouted.
--
-- Exposing the public one also takes an entry in `[api] schemas` in
-- config.toml AND the hosted project's exposed-schema dashboard setting, which
-- is state no migration can carry — see supabase/README.md, updated alongside
-- this file.
--
-- THE HIDDEN TABLES ARE DEFAULT-DENY HERE, DELIBERATELY. wavelength_cards and
-- wavelength_targets hold what only a round's psychic may ever see, and the
-- policies that let the psychic read them are #98 — built, with their leak
-- test, before any gameplay depends on them. Until then they have RLS enabled,
-- no policy and no grant, so no client role can read them at all. That is the
-- safe place to be in the meantime, not an omission.
--
-- `matches.game` already allows 'wavelength_2v2' (0051 named it, 0078 kept it),
-- so unlike 0051 there is no registry change to make.

-- ------------------------------------------------------------------ schemas --

create schema if not exists wavelength;
create schema if not exists wavelength_private;

revoke all on schema wavelength_private from public, anon, authenticated;

revoke all on schema wavelength from public;
grant usage on schema wavelength to anon, authenticated, service_role;

-- ------------------------------------------------------------------- config --

-- Every tunable in one place. The design doc calls these decisions "tunable"
-- because several are guesses to be settled by playtesting — wedge width above
-- all — so a change is one migration replacing this function, and nothing else
-- in the game hardcodes any of them.
--
-- Positions live on a 0..scale_max line across the dial. `wedge_width` is the
-- width of ONE of the five scoring wedges on that line (40 is ~4% of the arc,
-- so the whole 2/3/4/3/2 zone is 200, ~20%); the physical board's real widths
-- are not published, so this is a starting guess.
--
-- Timers: the fill clock is one clock for the whole phase, scaled by how many
-- clues each player has to write; the guess clock is per guess. Sudden death
-- reuses both.
--
-- Presets are co-op only. `rounds` is the total; each of the two players is
-- the psychic for half. star2/star3 are the score thresholds for the second
-- and third stars; the first star is reaching `target`.
create function wavelength_private.config()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'scale_max',             1000,
    'wedge_width',           40,
    'clue_max_words',        8,
    'clue_max_chars',        100,
    'fill_seconds_per_clue', 40,
    'guess_seconds',         30,
    'versus_rounds',         8,
    'presets', jsonb_build_object(
      'short',  jsonb_build_object('rounds', 4, 'target',  8, 'star2', 12, 'star3', 15),
      'medium', jsonb_build_object('rounds', 6, 'target', 12, 'star2', 18, 'star3', 22),
      'long',   jsonb_build_object('rounds', 8, 'target', 20, 'star2', 24, 'star3', 29)
    )
  );
$$;

-- --------------------------------------------------------------------- deck --

-- The approved spectrum cards, hand-authored and football-only
-- (docs/games/wavelength_cards.md). `card_id` is the number each card carries
-- in that review file, so a card can be traced back to it. No endpoint, no
-- policy, never in a publication: the deck is the dealer's input, and a match
-- gets its own copy of the labels it was dealt (wavelength_cards below) so
-- editing the deck later never rewrites a finished match.
create table wavelength_private.deck (
  card_id     int  primary key,
  left_label  text not null check (left_label  <> ''),
  right_label text not null check (right_label <> '')
);

revoke all on table wavelength_private.deck from public, anon, authenticated;
alter table wavelength_private.deck enable row level security;

insert into wavelength_private.deck (card_id, left_label, right_label) values
  (1, 'Overrated QB', 'Underrated QB'),
  (3, 'Worst stadium food', 'Best stadium food'),
  (4, 'Player you''d never party with', 'Player you''d want to party with'),
  (5, 'Easy fanbase to like', 'Hard fanbase to like'),
  (6, 'Ugly uniform', 'Beautiful uniform'),
  (7, 'Weak touchdown celebration', 'Elite touchdown celebration'),
  (8, 'Cold-weather team', 'Warm-weather team'),
  (9, 'Quiet stadium', 'Loud stadium'),
  (10, 'Boring play call', 'Gutsy play call'),
  (11, 'Hard-to-watch offense', 'Fun-to-watch offense'),
  (12, 'Soft team', 'Tough team'),
  (13, 'Mild rivalry', 'Great rivalry'),
  (14, 'Overrated position', 'Underrated position'),
  (15, 'Shrug-it-off loss', 'Heartbreaking loss'),
  (16, 'Forgettable Super Bowl', 'Legendary Super Bowl'),
  (17, 'Bad halftime show', 'Great halftime show'),
  (18, 'Kicker you''d panic over', 'Kicker you''d trust'),
  (19, 'Nobody''s favorite team', 'Everybody''s favorite team'),
  (20, 'Coach you''d hate to play for', 'Coach you''d love to play for'),
  (21, 'Weak trash talk', 'Elite trash talk'),
  (22, 'Average tailgate', 'Elite tailgate'),
  (23, 'Dad''s favorite player', 'Gen Z''s favorite player'),
  (24, 'Old-school football', 'Modern football'),
  (25, 'Draft bust', 'Draft steal'),
  (26, 'Fantasy football bust', 'Fantasy football hero'),
  (27, 'Rebuilding team', 'Super Bowl contender'),
  (28, 'Player everyone hates', 'Player everyone loves'),
  (29, 'Dumb penalty', 'Smart penalty'),
  (30, 'Bad mascot', 'Great mascot'),
  (31, 'Harmless defense', 'Terrifying defense'),
  (32, 'Lineman nobody knows', 'Lineman everybody knows'),
  (33, 'Worst city to visit for a game', 'Best city to visit for a game'),
  (34, 'Bad broadcaster', 'Great broadcaster'),
  (35, 'Skippable game', 'Must-watch game'),
  (37, 'Too safe on fourth down', 'Too reckless on fourth down'),
  (38, 'Quarterback with no swagger', 'Quarterback with all the swagger'),
  (39, 'Player who''d lose a fight', 'Player who''d win a fight'),
  (40, 'Lukewarm take', 'Scorching take'),
  (41, 'Normal pregame ritual', 'Bizarre pregame ritual'),
  (42, 'Easy to root against', 'Impossible to root against'),
  (61, 'Not a Hall of Famer', 'Hall of Fame lock'),
  (62, 'Pocket passer', 'Scrambler'),
  (63, 'Bruiser running back', 'Elusive running back'),
  (64, 'Possession receiver', 'Deep threat'),
  (65, 'Finesse pass rusher', 'Power pass rusher'),
  (66, 'Quiet professional', 'Loud personality'),
  (67, 'Mistake-prone', 'Mistake-free'),
  (68, 'One-hit wonder', 'Longevity king'),
  (69, 'Unknown rookie', 'Household name'),
  (70, 'Fantasy sleeper', 'Fantasy first-rounder'),
  (71, 'Clean player', 'Dirty player'),
  (72, 'Chokes in big games', 'Clutch in big games'),
  (73, 'Locker-room cancer', 'Locker-room leader'),
  (74, 'Overpaid', 'Underpaid'),
  (75, 'Injury-prone', 'Iron man'),
  (76, 'Washed', 'Still elite'),
  (77, 'Gadget player', 'Every-down player'),
  (78, 'Stat-padder', 'Winner'),
  (79, 'Combine warrior', 'Plays better than he tests'),
  (80, 'Beloved by the media', 'Hated by the media'),
  (81, 'Preseason hero', 'Actual contributor'),
  (82, 'Pickup-game MVP', 'Pickup-game liability'),
  (83, 'Backup QB you''d fear', 'Backup QB you''d trust'),
  (84, 'Madden rating too low', 'Madden rating too high'),
  (85, 'Boring on social media', 'Entertaining on social media'),
  (86, 'Wooden in commercials', 'Natural in commercials'),
  (87, 'Boring when mic''d up', 'Hilarious when mic''d up'),
  (88, 'Terrible analyst', 'Great analyst'),
  (89, 'Boring dynasty', 'Fun dynasty'),
  (90, 'Perennial loser', 'Perennial winner'),
  (91, 'Small-market team', 'Big-market team'),
  (92, 'Franchise in chaos', 'Franchise with stability'),
  (93, 'Front-office clown', 'Front-office genius'),
  (94, 'Team you''d never bet on', 'Team you''d bet the house on'),
  (95, 'Old and charming stadium', 'New and shiny stadium'),
  (96, 'Players'' coach', 'Disciplinarian'),
  (97, 'Hot-seat coach', 'Untouchable coach'),
  (98, 'Fanbase with no patience', 'Fanbase with endless patience'),
  (99, 'Matchup you dread', 'Matchup you want'),
  (100, 'Free-agency overspend', 'Free-agency bargain'),
  (101, 'Draft pick fans booed', 'Draft pick fans cheered'),
  (102, 'Jersey nobody owns', 'Jersey everybody owns'),
  (103, 'Forgettable play', 'Iconic play'),
  (104, 'Terrible trade', 'Great trade'),
  (105, 'Obvious call', 'Controversial call'),
  (106, 'Snoozer blowout', 'Instant classic'),
  (107, 'Terrible rule', 'Great rule'),
  (108, 'Easy-to-explain rule', 'Impossible-to-explain rule'),
  (109, 'Glamour position', 'Grunt position'),
  (110, 'Ground-and-pound', 'Air raid'),
  (111, 'Bend-don''t-break defense', 'Blitz-happy defense'),
  (112, 'Trick play too cute', 'Trick play genius'),
  (113, 'Ugly win', 'Beautiful win'),
  (114, 'Wasted timeout', 'Perfectly timed timeout'),
  (115, 'Lucky play', 'Skilled play'),
  (116, 'Playing for the paycheck', 'Playing for the love of the game'),
  (117, 'Coin-flip game', 'Lock of the week'),
  (121, 'Shutdown corner', 'Ball-hawking gambler'),
  (122, 'Sack artist', 'Run stopper'),
  (123, 'Blocking tight end', 'Receiving tight end'),
  (124, 'Homegrown star', 'Hired gun'),
  (126, 'Fades late', 'Finishes strong'),
  (127, 'Top-heavy roster', 'Deep roster'),
  (128, 'Rookie who needs time', 'Rookie ready now');

-- ------------------------------------------------------------------- tables --

-- The match's mode and pointer. `mode` is 'versus' (four players, two
-- competing teams) or 'coop' (two players, one team, a target score in a fixed
-- number of rounds). A preset exists exactly when the mode is co-op.
-- `current_round` is not bounded by `round_count`: sudden death (#102) adds
-- rounds past it.
create table public.wavelength_matches (
  match_id       uuid     primary key references public.matches (id) on delete cascade,
  mode           text     not null check (mode in ('versus', 'coop')),
  preset         text     check (preset in ('short', 'medium', 'long')),
  round_count    smallint not null check (round_count > 0),
  current_round  smallint not null default 1 check (current_round >= 1),
  phase          text     not null default 'fill' check (phase in ('fill', 'guess', 'reveal', 'complete')),
  phase_deadline timestamptz,

  constraint wavelength_matches_preset_iff_coop check ((mode = 'coop') = (preset is not null))
);

-- Who is playing. Seats are copied from run_participants rather than shuffled
-- again, for the reason 0032 gives: the platform froze the order at run start.
-- `team` is 0 or 1; in co-op both players are on team 0. Presence is stamped
-- by the timer slice (#101).
create table public.wavelength_players (
  match_id     uuid        not null references public.matches (id) on delete cascade,
  user_id      uuid        not null references public.profiles (id),
  seat         smallint    not null,
  team         smallint    not null check (team in (0, 1)),
  last_seen_at timestamptz not null default now(),
  absent       boolean     not null default false,

  primary key (match_id, user_id),
  unique (match_id, seat)
);

-- One row per round: who is the psychic, who guesses. Deliberately carries
-- nothing hidden yet — no clue, no revealed target. Those columns arrive with
-- the slices that give them a policy (#98, #99, #100), so nothing a client can
-- read here could leak before its rule exists.
create table public.wavelength_rounds (
  match_id   uuid     not null references public.matches (id) on delete cascade,
  round      smallint not null check (round >= 1),
  psychic_id uuid     not null references public.profiles (id),
  guesser_id uuid     not null references public.profiles (id),
  status     text     not null default 'pending' check (status in ('pending', 'open', 'locked', 'skipped')),
  points     smallint check (points between 0 and 4),

  primary key (match_id, round),
  check (psychic_id <> guesser_id)
);

-- The card a round was dealt: a copy of the deck's labels. HIDDEN — see the
-- header. `unique (match_id, card_id)` is the no-repeat-within-a-match rule
-- enforced by the schema, not only by the dealer.
create table public.wavelength_cards (
  match_id    uuid     not null,
  round       smallint not null,
  card_id     int      not null references wavelength_private.deck (card_id),
  left_label  text     not null,
  right_label text     not null,

  primary key (match_id, round),
  foreign key (match_id, round) references public.wavelength_rounds (match_id, round) on delete cascade,
  unique (match_id, card_id)
);

-- The target: a position on the 0..1000 line, the CENTRE of the five scoring
-- wedges. HIDDEN — see the header. It lives in its own table because RLS hides
-- whole rows, not columns, so it cannot sit on the round row everyone reads.
create table public.wavelength_targets (
  match_id uuid     not null,
  round    smallint not null,
  target   smallint not null check (target between 0 and 1000),

  primary key (match_id, round),
  foreign key (match_id, round) references public.wavelength_rounds (match_id, round) on delete cascade
);

-- Existence only: "this round's clue is written", visible to the whole table
-- without revealing the clue — the split 0034 makes between calls and
-- call_statuses. Written by submit_clue (#99).
create table public.wavelength_clue_statuses (
  match_id uuid     not null,
  round    smallint not null,

  primary key (match_id, round),
  foreign key (match_id, round) references public.wavelength_rounds (match_id, round) on delete cascade
);

-- The structured result of a finished match: what any later party-point
-- mapping reads, so it can be applied without touching the game. The outcome
-- vocabulary and the versus shape are settled by #102; this holds the columns
-- every outcome has.
create table public.wavelength_results (
  match_id  uuid     primary key references public.matches (id) on delete cascade,
  mode      text     not null check (mode in ('versus', 'coop')),
  preset    text     check (preset in ('short', 'medium', 'long')),
  outcome   text     not null,
  score     smallint not null,
  bullseyes smallint not null,
  stars     smallint check (stars between 0 and 3)
);

-- ---------------------------------------------------------------------- RLS --

alter table public.wavelength_matches        enable row level security;
alter table public.wavelength_players        enable row level security;
alter table public.wavelength_rounds         enable row level security;
alter table public.wavelength_cards          enable row level security;
alter table public.wavelength_targets        enable row level security;
alter table public.wavelength_clue_statuses  enable row level security;
alter table public.wavelength_results        enable row level security;

-- Explicit, not inherited: a hosted project grants new public tables to
-- anon/authenticated by default (see the note on seed.sql in
-- supabase/README.md), and these two must never be reachable by accident.
revoke all on public.wavelength_matches        from anon, authenticated;
revoke all on public.wavelength_players        from anon, authenticated;
revoke all on public.wavelength_rounds         from anon, authenticated;
revoke all on public.wavelength_cards          from anon, authenticated;
revoke all on public.wavelength_targets        from anon, authenticated;
revoke all on public.wavelength_clue_statuses  from anon, authenticated;
revoke all on public.wavelength_results        from anon, authenticated;

create policy wavelength_matches_select_member on public.wavelength_matches
  for select to authenticated using (private.is_match_member(match_id));
create policy wavelength_players_select_member on public.wavelength_players
  for select to authenticated using (private.is_match_member(match_id));
create policy wavelength_rounds_select_member on public.wavelength_rounds
  for select to authenticated using (private.is_match_member(match_id));
create policy wavelength_clue_statuses_select_member on public.wavelength_clue_statuses
  for select to authenticated using (private.is_match_member(match_id));
create policy wavelength_results_select_member on public.wavelength_results
  for select to authenticated using (private.is_match_member(match_id));

-- wavelength_cards and wavelength_targets: no policy and no grant. See the
-- header. #98 adds the psychic-only policies and the leak test.

-- No INSERT/UPDATE/DELETE policy anywhere, consistent with every table since
-- 0003: every write goes through a definer function.
grant select on public.wavelength_matches       to authenticated;
grant select on public.wavelength_players       to authenticated;
grant select on public.wavelength_rounds        to authenticated;
grant select on public.wavelength_clue_statuses to authenticated;
grant select on public.wavelength_results       to authenticated;

-- ----------------------------------------------------------------- realtime --
-- The five tables with something every member may see, and neither hidden one.
-- RLS applies to replication, so these fan out only to players in the match.

alter publication supabase_realtime add table public.wavelength_matches;
alter publication supabase_realtime add table public.wavelength_players;
alter publication supabase_realtime add table public.wavelength_rounds;
alter publication supabase_realtime add table public.wavelength_clue_statuses;
alter publication supabase_realtime add table public.wavelength_results;

-- --------------------------------------------------------------- the deal --

-- Deals a whole match in one transaction: a half-dealt match is a broken one.
--
--   * Teams: random for versus (two pairs); one team for co-op.
--   * Rounds: versus is config.versus_rounds, 8 (4 players x 2 clues each),
--     and the psychic cycles a1, b1, a2, b2 so teams alternate every round.
--     Co-op is the preset's round count and the two players alternate.
--     The guesser is always the psychic's teammate.
--   * Cards: drawn without replacement within the match.
--   * Targets: a centre drawn so the whole five-wedge zone fits on the line.
--   * Fill clock: one clock for the whole phase, scaled by the number of
--     clues each player writes (rounds / players).
--
-- The seed is an argument so tests can pin a board, the reason the other
-- dealers take one. Deliberately NOT an argument of the public entry point
-- (wavelength.start, below): a client that chose the seed could precompute
-- every round's target from the dealer in this repository.
create function wavelength_private.deal_board(
  p_match_id uuid,
  p_mode     text,
  p_preset   text default null,
  p_seed     double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg     jsonb := wavelength_private.config();
  v_seed    double precision := coalesce(p_seed, random());
  v_scale   int := (v_cfg ->> 'scale_max')::int;
  -- Half the five-wedge zone: the centre must sit at least this far from both
  -- ends of the line for the whole 2/3/4/3/2 zone to fit on it.
  v_margin  int := (v_cfg ->> 'wedge_width')::int * 5 / 2;
  v_rounds  int;
  v_n       int;
  v_cycle   uuid[];
  v_team0   uuid[];
  v_team1   uuid[];
  v_used    int[] := '{}';
  v_card    record;
  v_i       int;
  v_psychic uuid;
  v_guesser uuid;
begin
  if p_mode is null or p_mode not in ('versus', 'coop') then
    raise exception 'invalid_mode' using errcode = 'P0001';
  end if;

  -- A preset belongs to co-op and only co-op.
  if p_mode = 'coop' then
    if p_preset is null or not (v_cfg -> 'presets') ? p_preset then
      raise exception 'invalid_preset' using errcode = 'P0001';
    end if;
    v_rounds := (v_cfg -> 'presets' -> p_preset ->> 'rounds')::int;
  else
    if p_preset is not null then
      raise exception 'invalid_preset' using errcode = 'P0001';
    end if;
    v_rounds := (v_cfg ->> 'versus_rounds')::int;
  end if;

  select count(*) into v_n
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  -- The platform's start_run accepts 2 to 4 players; what a mode needs is this
  -- game's business, not the platform's. A lobby of three fits neither.
  if (p_mode = 'versus' and v_n <> 4) or (p_mode = 'coop' and v_n <> 2) then
    raise exception 'player_count_mismatch' using errcode = 'P0001';
  end if;

  -- Parallelism off for the duration, the same reason every other dealer turns
  -- it off: a parallel worker has its own PRNG state, and the seed would stop
  -- meaning anything.
  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  -- random() in the subquery target list is what pins the shuffle (see 0009).
  insert into public.wavelength_players (match_id, user_id, seat, team)
  select p_match_id, s.user_id, s.seat,
         case when p_mode = 'coop' then 0
              else ((row_number() over (order by s.r) - 1) / 2)::smallint
         end
    from (
      select rp.user_id, rp.seat, random() as r
        from public.run_participants rp
        join public.matches m on m.run_id = rp.run_id
       where m.id = p_match_id
    ) s;

  if p_mode = 'versus' then
    select array_agg(user_id order by seat) into v_team0
      from public.wavelength_players where match_id = p_match_id and team = 0;
    select array_agg(user_id order by seat) into v_team1
      from public.wavelength_players where match_id = p_match_id and team = 1;
    v_cycle := array[v_team0[1], v_team1[1], v_team0[2], v_team1[2]];
  else
    select array_agg(user_id order by seat) into v_cycle
      from public.wavelength_players where match_id = p_match_id;
  end if;

  for v_i in 1 .. v_rounds loop
    v_psychic := v_cycle[(v_i - 1) % array_length(v_cycle, 1) + 1];

    select wp.user_id into v_guesser
      from public.wavelength_players wp
     where wp.match_id = p_match_id
       and wp.user_id <> v_psychic
       and wp.team = (select team from public.wavelength_players
                       where match_id = p_match_id and user_id = v_psychic);

    insert into public.wavelength_rounds (match_id, round, psychic_id, guesser_id)
    values (p_match_id, v_i, v_psychic, v_guesser);

    select d.card_id, d.left_label, d.right_label into v_card
      from wavelength_private.deck d
     where d.card_id <> all (v_used)
     order by random()
     limit 1;

    if not found then
      raise exception 'deck_exhausted' using errcode = 'P0001';
    end if;
    v_used := v_used || v_card.card_id;

    insert into public.wavelength_cards (match_id, round, card_id, left_label, right_label)
    values (p_match_id, v_i, v_card.card_id, v_card.left_label, v_card.right_label);

    insert into public.wavelength_targets (match_id, round, target)
    values (p_match_id, v_i, v_margin + floor(random() * (v_scale - 2 * v_margin + 1))::int);
  end loop;

  insert into public.wavelength_matches (match_id, mode, preset, round_count, current_round, phase, phase_deadline)
  values (
    p_match_id, p_mode, p_preset, v_rounds, 1, 'fill',
    now() + make_interval(secs => (v_rounds / v_n) * (v_cfg ->> 'fill_seconds_per_clue')::int)
  );
end;
$$;

-- --------------------------------------------------------- the entry points --

-- What a client is told about the match. A projection, not the table: adding a
-- column to wavelength_matches must never be silently also a decision to
-- publish it. `server_now` feeds useMatchClock's offset measurement.
create type wavelength.board as (
  match_id       uuid,
  mode           text,
  preset         text,
  round_count    smallint,
  current_round  smallint,
  phase          text,
  phase_deadline timestamptz,
  server_now     timestamptz
);

create function wavelength_private.board_of(p_match_id uuid)
returns wavelength.board
language sql
stable
security definer
set search_path = ''
as $$
  select (m.match_id, m.mode, m.preset, m.round_count, m.current_round,
          m.phase, m.phase_deadline, now())::wavelength.board
    from public.wavelength_matches m
   where m.match_id = p_match_id;
$$;

-- The reconnect contract: any match member can ask where the table is.
create function wavelength.state(p_match_id uuid)
returns wavelength.board
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  return wavelength_private.board_of(p_match_id);
end;
$$;

-- Called once, by any participant, right after start_run returns a 'setup'
-- match. Takes no seed, on purpose — see the dealer. A rejected deal (a wrong
-- mode, a player count that doesn't fit it) raises, so the transaction rolls
-- back and the match is still 'setup'.
create function wavelength.start(
  p_match_id uuid,
  p_mode     text,
  p_preset   text default null
)
returns wavelength.board
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

  -- The lock is what makes "deal twice" impossible rather than unlikely.
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  if v_match.game <> 'wavelength_2v2' then
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

  perform wavelength_private.deal_board(p_match_id, p_mode, p_preset, null);

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  return wavelength_private.board_of(p_match_id);
end;
$$;

-- --------------------------------------------------------------- privileges --
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. Take it back, then hand
-- out only what a signed-in player is allowed to ask for.

revoke all on function wavelength_private.config()  from public, anon, authenticated;
revoke all on function wavelength_private.board_of(uuid) from public, anon, authenticated;
revoke all on function wavelength_private.deal_board(uuid, text, text, double precision)
  from public, anon, authenticated;

revoke all on function wavelength.state(uuid) from public, anon;
revoke all on function wavelength.start(uuid, text, text) from public, anon;

grant execute on function wavelength.state(uuid) to authenticated;
grant execute on function wavelength.start(uuid, text, text) to authenticated;
