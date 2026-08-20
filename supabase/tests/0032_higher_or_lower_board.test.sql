-- Tests for the Higher or Lower board and its dealer (migration 0032).
--
-- Two of these are the point of the file.
--
-- The leak test deals a ladder and asserts that no client-reachable relation
-- carries an unrevealed card's points or its quantile — read as a participant,
-- under RLS, plus the privilege and publication facts behind that. It is the
-- same assertion the auction's 0010 makes and for the same reason: this failure
-- would go through the Realtime payload rather than through a screen, so
-- nothing anybody looked at would show it.
--
-- The band test asserts the property the whole dealer exists to produce — every
-- consecutive pair sits inside the band for its question index, and the band at
-- question twelve is tighter than at question one. Difficulty is a rule here,
-- not a decoration.

begin;
select plan(63);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m4', tests.deal_higher_or_lower(4, 0.25));
select tests.act_as_admin();

-- ------------------------------------------------------------- composition --

select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4')),
  18,
  'a board is a seed anchor, twelve questions and five spares'
);

select is(
  (select array_agg(ordinal order by ordinal) from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4')),
  (select array_agg(g::smallint order by g) from generate_series(0, 17) g),
  'and their ordinals run 0..17 without a gap, since ordinal is play order'
);

select is(
  (select question_count::int from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'm4')),
  12,
  'the match records the question count it was dealt for'
);

select is(
  (select spare_count::int from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'm4')),
  5,
  'and the spares sudden death will consume'
);

select is(
  (select scoring_mode from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'm4')),
  'season_total',
  'and the resolved scoring mode, so a finished board stays readable if the default is retuned'
);

select is(
  (select array[season_from, season_to] from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'm4')),
  (select array[b.season_min, b.season_max] from higher_or_lower_private.season_bounds() b),
  'and the era bounds, which default to the whole pool rather than a written-down year'
);

select is(
  (select array_agg(seat order by seat) from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm4')),
  array[0, 1, 2, 3]::smallint[],
  'every seated player gets a row'
);

select ok(
  not exists (
    select 1
      from public.higher_or_lower_players hp
      join public.matches mt on mt.id = hp.match_id
      join public.run_participants rp on rp.run_id = mt.run_id and rp.user_id = hp.user_id
     where hp.match_id = (select v from tests.fx where k = 'm4')
       and hp.seat is distinct from rp.seat
  ),
  'and seats are copied from run_participants rather than shuffled again'
);

-- --------------------------------------------------------------- the cards --

select ok(
  (select bool_and(display_name <> '' and position in ('QB','RB','WR','TE') and season > 0 and team <> '')
     from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4')),
  'a card carries the recall cues: name, position, season and team'
);

select ok(
  (select bool_and(week is null and opponent is null)
     from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4')),
  'and no week or opponent in season mode, where a card is a whole season'
);

-- Left join in spirit: a player the headshot table has not caught up with still
-- deals a perfectly good card. So this asserts the copy is right where it
-- happened, and — the one clause here that depends on the deal rather than on a
-- rule — that it happened at all, without which the equality below would pass
-- on a board of eighteen nulls.
select ok(
  (select count(*) > 0 from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4') and headshot_url is not null)
  and not exists (
    select 1 from public.higher_or_lower_cards c
      left join private.player_headshots h on h.player_id = c.player_id
     where c.match_id = (select v from tests.fx where k = 'm4')
       and c.headshot_url is distinct from h.headshot_url
  ),
  'and the headshot the pool holds for that player, where it holds one'
);

select is(
  (select count(distinct player_id)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4')),
  18,
  'no player appears twice in one ladder — distinctness is by player, not by card'
);

-- ---------------------------------------------------------------- the band --

-- Quantiles come from percent_rank over the deck, which gives tied points a
-- tied rank, so a strictly positive distance between two cards is a guarantee
-- their points differ. This asserts the consequence rather than the mechanism.
select ok(
  not exists (
    select 1
      from higher_or_lower_private.answers a
      join higher_or_lower_private.answers b
        on b.match_id = a.match_id and b.ordinal = a.ordinal + 1
     where a.match_id = (select v from tests.fx where k = 'm4')
       and a.points = b.points
  ),
  'no two consecutive cards have equal points, so every question has a right answer'
);

-- The property the dealer exists to produce. The tolerance is float noise on a
-- boundary comparison the dealer made with the same arithmetic, not slack in
-- the rule.
select ok(
  not exists (
    select 1
      from higher_or_lower_private.answers a
      join higher_or_lower_private.answers b
        on b.match_id = a.match_id and b.ordinal = a.ordinal + 1
      cross join lateral higher_or_lower_private.band(b.ordinal) sched
     where a.match_id = (select v from tests.fx where k = 'm4')
       and abs(b.quantile - a.quantile) not between sched.band_min - 1e-9 and sched.band_max + 1e-9
  ),
  'every consecutive pair sits inside the band for its question index'
);

select ok(
  (select b12.band_min < b1.band_min
      and b12.band_max < b1.band_max
      and (b12.band_max - b12.band_min) < (b1.band_max - b1.band_min)
     from higher_or_lower_private.band(1) b1, higher_or_lower_private.band(12) b12),
  'and question twelve is a tighter call than question one'
);

select ok(
  (select abs(b.band_min - 0.20) < 1e-9 and abs(b.band_max - 0.35) < 1e-9
     from higher_or_lower_private.band(1) b),
  'question one asks for a fifth to a third of the deck between the two cards'
);

select ok(
  (select b13.band_min < b12.band_min
     from higher_or_lower_private.band(12) b12, higher_or_lower_private.band(13) b13),
  'the schedule keeps tightening past the question count, which solo will ask it to do'
);

-- The floor is the reason the schedule decays rather than descending. A linear
-- one extended far enough reaches zero and then goes negative, and a question
-- with no distance between its cards is a coin flip.
select ok(
  (select b.band_min >= 0.04 and b.band_min - 0.04 < 1e-9
      and b.band_max >= 0.10 and b.band_max - 0.10 < 1e-9
     from higher_or_lower_private.band(1000) b),
  'but it settles on a floor rather than tightening without bound'
);

-- ------------------------------------------------------------- the answers --
--
-- This is the point of the whole module.

select is(
  (select count(*)::int from higher_or_lower_private.answers
    where match_id = (select v from tests.fx where k = 'm4')),
  18,
  'every card has an answer stored'
);

select ok(
  not exists (
    select 1 from public.higher_or_lower_cards c
      join higher_or_lower_private.answers a
        on a.match_id = c.match_id and a.ordinal = c.ordinal
      join private.player_seasons s
        on s.player_id = c.player_id and s.season = c.season
     where c.match_id = (select v from tests.fx where k = 'm4')
       and a.points is distinct from s.points
  ),
  'and it is the real fantasy points for that player-season'
);

select ok(
  (select points is not null and revealed_at is not null
     from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4') and ordinal = 0),
  'the seed anchor is dealt face up — a player needs one number to price the first card against'
);

select is(
  (select c.points from public.higher_or_lower_cards c
    where c.match_id = (select v from tests.fx where k = 'm4') and c.ordinal = 0),
  (select a.points from higher_or_lower_private.answers a
    where a.match_id = (select v from tests.fx where k = 'm4') and a.ordinal = 0),
  'and the face-up number is a copy of the answer, which is what a reveal is'
);

select ok(
  (select bool_and(points is null and revealed_at is null)
     from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4') and ordinal > 0),
  'no challenger carries its points'
);

-- ------------------------------------------------------ reproducibility --

insert into tests.fx (k, v) values ('m4_same',  tests.deal_higher_or_lower(4, 0.25));
insert into tests.fx (k, v) values ('m4_other', tests.deal_higher_or_lower(4, 0.9));
select tests.act_as_admin();

-- Card by card, and by the whole card rather than by player: a player id does
-- not pin a season, so two ladders differing in season, points and quantile
-- would pass an assertion made on names alone.
select is(
  (select array_agg(c.player_id || ':' || c.season || ':' || a.points order by c.ordinal)
     from public.higher_or_lower_cards c
     join higher_or_lower_private.answers a
       on a.match_id = c.match_id and a.ordinal = c.ordinal
    where c.match_id = (select v from tests.fx where k = 'm4_same')),
  (select array_agg(c.player_id || ':' || c.season || ':' || a.points order by c.ordinal)
     from public.higher_or_lower_cards c
     join higher_or_lower_private.answers a
       on a.match_id = c.match_id and a.ordinal = c.ordinal
    where c.match_id = (select v from tests.fx where k = 'm4')),
  'the same seed deals an identical ladder, card for card'
);

select isnt(
  (select array_agg(player_id order by ordinal) from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4_other')),
  (select array_agg(player_id order by ordinal) from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4')),
  'a different seed does not'
);

select is(
  (select seed from higher_or_lower_private.boards
    where match_id = (select v from tests.fx where k = 'm4')),
  0.25::double precision,
  'the seed is stored, so a ladder somebody complains about can be dealt again'
);

-- The seed is an answer key: the dealer is in the repository, the band schedule
-- is in the repository, and the source data is public.
select hasnt_column('public', 'higher_or_lower_matches', 'seed',
  'the seed is not on the client-readable match row');

select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'higher_or_lower_private' and tablename = 'boards'
  ),
  'and the table holding it is in no publication'
);

-- ------------------------------------------------------------ table sizes --

-- The ladder is the same length whoever is at the table — unlike the auction,
-- whose board is 5N. Nothing about the deal scales with the roster, and this is
-- what says so across the lobby's whole capacity.
insert into tests.fx (k, v) values ('m3', tests.deal_higher_or_lower(3, 0.6));
insert into tests.fx (k, v) values ('m2', tests.deal_higher_or_lower(2, 0.7));
select tests.act_as_admin();

select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm3')),
  18,
  'a three-player table gets the same eighteen cards'
);

select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm2')),
  18,
  'and so does a two-player table'
);

select is(
  (select array_agg(seat order by seat) from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm3')),
  array[0, 1, 2]::smallint[],
  'each seating exactly the players the run froze'
);

-- ------------------------------------------------------------ the era window --

insert into tests.fx (k, v) values
  ('m_era', tests.deal_higher_or_lower(2, 0.4, 'season_total', 2020::smallint, 2022::smallint));
select tests.act_as_admin();

select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm_era')),
  18,
  'a narrow era window still deals a complete board'
);

select ok(
  (select bool_and(season between 2020 and 2022) from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm_era')),
  'drawn only from the seasons the host asked for'
);

select is(
  (select array[season_from, season_to] from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'm_era')),
  array[2020, 2022]::smallint[],
  'and the match records the window it was dealt from'
);

-- The band is a quantile, so it normalises to whatever deck is in play. A
-- narrower deck is a different set of numbers and the same rule.
--
-- Deliberately stricter than the dealer's contract, which allows it to widen
-- the band when neither direction has a candidate — a widened draw would fail
-- this. That is the assertion: widening is a backstop for windows narrower than
-- anything the game offers, and if a three-season window trips it, the band is
-- wrong rather than the test.
select ok(
  not exists (
    select 1
      from higher_or_lower_private.answers a
      join higher_or_lower_private.answers b
        on b.match_id = a.match_id and b.ordinal = a.ordinal + 1
      cross join lateral higher_or_lower_private.band(b.ordinal) sched
     where a.match_id = (select v from tests.fx where k = 'm_era')
       and abs(b.quantile - a.quantile) not between sched.band_min - 1e-9 and sched.band_max + 1e-9
  ),
  'and its band holds too, over the deck that window selects'
);

select throws_ok(
  $$ select higher_or_lower_private.resolve_season_range(2022::smallint, 2020::smallint) $$,
  'P0001', 'invalid_season_range',
  'a range that runs backwards is refused rather than reordered'
);

select throws_ok(
  $$ select higher_or_lower_private.resolve_season_range(1999::smallint, 2020::smallint) $$,
  'P0001', 'season_out_of_range',
  'and one reaching outside the pool is refused rather than clamped'
);

-- ------------------------------------------------------------- the leak --

-- Read as a participant, under RLS, which is the shape a browser actually sees.
select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm4')
   order by rp.seat limit 1
));

select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4')),
  18,
  'a participant can read the board'
);

select ok(
  (select bool_and(points is null) from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm4') and ordinal > 0),
  'and every unrevealed points column they can see is null'
);

select throws_ok(
  'select count(*) from higher_or_lower_private.answers',
  '42501',
  null,
  'the answers are not reachable from an authenticated session at all'
);

select throws_ok(
  'select count(*) from higher_or_lower_private.boards',
  '42501',
  null,
  'nor is the seed'
);

select tests.act_as_admin();

-- The facts that back that up, asserted directly because they are what a future
-- migration could widen by accident.
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'higher_or_lower_private'
       and grantee in ('anon', 'authenticated', 'PUBLIC')
  ),
  'no client role holds any privilege on any table in the engine schema'
);

select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'higher_or_lower_private'
  ),
  'and nothing in it is in a publication, so Realtime can never replicate it'
);

select bag_eq(
  $$ select tablename::text from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename like 'higher_or_lower%' $$,
  $$ values ('higher_or_lower_matches'), ('higher_or_lower_cards'),
            ('higher_or_lower_players'), ('higher_or_lower_calls'),
            ('higher_or_lower_call_statuses') $$,
  'the client-readable ladder and call projections are replicated, and only those'
);

-- The quantile is not just this card's answer, it is its rank in the deck. Easy
-- to add to the readable row later by accident.
select hasnt_column('public', 'higher_or_lower_cards', 'quantile',
  'a card does not carry its quantile — that would place it in the distribution');
select hasnt_column('public', 'higher_or_lower_cards', 'tier',
  'nor its tier');

-- ------------------------------------------------------- the module boundary --

select ok(
  has_schema_privilege('authenticated', 'higher_or_lower', 'usage'),
  'a participant can reach the write-API schema'
);

select ok(
  not has_schema_privilege('authenticated', 'higher_or_lower_private', 'usage'),
  'but not the engine schema — the same shape private has had since 0004'
);

select ok(
  not has_schema_privilege('anon', 'higher_or_lower_private', 'usage'),
  'and anon cannot either'
);

select bag_eq(
  $$ select p.proname::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'higher_or_lower' $$,
  $$ values ('call'), ('season_bounds'), ('start'), ('state'), ('tick') $$,
  'the exposed schema holds exactly the client RPCs for the dealt ladder'
);

select ok(
  (select bool_and(p.proname = 'has_called' or not has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'higher_or_lower_private'),
  'only the policy helper is executable by a participant; every engine entry remains private'
);

select ok(
  (select count(*) > 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'higher_or_lower_private'),
  'and that assertion is not vacuous — the engine schema is populated'
);

-- --------------------------------------------------------------- refusals --

-- Constructed, because start_run already refuses a one-person lobby: the
-- platform floor and the game floor are different rules that happen to agree at
-- N=1 today. This asserts the game's own floor exists rather than being assumed.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_thin', tests.mkmatch(2, 'higher_or_lower'));
select tests.act_as_admin();

delete from public.run_participants
 where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm_thin'))
   and seat = 1;

select throws_ok(
  format($$ select higher_or_lower_private.deal_board(%L, 0.1) $$, (select v from tests.fx where k = 'm_thin')),
  'P0001', 'too_few_players',
  'a one-player table is refused by the dealer, which is where a game floor belongs'
);

-- higher_or_lower.start is the real entry point: it checks the caller and the
-- state, and flips the match to playing.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_start', tests.mkmatch(4, 'higher_or_lower'));

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_start')
   order by rp.seat limit 1
));

select lives_ok(
  format($$ select higher_or_lower.start(%L) $$, (select v from tests.fx where k = 'm_start')),
  'a participant can start the game from a room of four'
);

select tests.act_as_admin();
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'm_start')),
  'playing',
  'starting it moves the match out of setup'
);

select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm_start')),
  18,
  'and the table has a board to look at'
);

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_start')
   order by rp.seat limit 1
));
select throws_ok(
  format($$ select higher_or_lower.start(%L) $$, (select v from tests.fx where k = 'm_start')),
  'P0001', 'match_not_setup',
  'a match that is already playing cannot be dealt again'
);

-- Somebody outside the run cannot start it.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('nosy'));
insert into tests.fx (k, v) values ('m_guard', tests.mkmatch(2, 'higher_or_lower'));

select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select higher_or_lower.start(%L) $$, (select v from tests.fx where k = 'm_guard')),
  '42501', 'not_a_participant',
  'someone who is not in the run cannot start its match'
);

-- Nor can this game deal into another game's match.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_auction', tests.mkmatch(2));

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_auction')
   order by rp.seat limit 1
));
select throws_ok(
  format($$ select higher_or_lower.start(%L) $$, (select v from tests.fx where k = 'm_auction')),
  'P0001', 'wrong_game',
  'and a match belonging to another game is refused'
);

-- Weekly draws its own player-week deck and keeps the same player distinct
-- throughout the ladder.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_weekly', tests.mkmatch(2, 'higher_or_lower'));
-- mkmatch leaves the session acting as the host, and the host cannot reach the
-- engine schema at all — which would turn both refusals below into 42501.
select tests.act_as_admin();

select lives_ok(
  format($$ select higher_or_lower_private.deal_board(%L, 0.1, 'weekly') $$,
         (select v from tests.fx where k = 'm_weekly')),
  'weekly scoring deals from its player-week deck'
);

select ok(
  (select bool_and(week is not null and opponent is not null) from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'm_weekly')),
  'weekly cards expose their week and opponent recall cues'
);

select is(
  (select count(*)::int from public.higher_or_lower_cards where match_id = (select v from tests.fx where k = 'm_weekly')),
  (select count(distinct player_id)::int from public.higher_or_lower_cards where match_id = (select v from tests.fx where k = 'm_weekly')),
  'weekly cards remain distinct by player'
);

select throws_ok(
  format($$ select higher_or_lower_private.deal_board(%L, 0.1, 'nonsense') $$,
         (select v from tests.fx where k = 'm_weekly')),
  'P0001', 'invalid_scoring_mode',
  'and a scoring mode that is not one of the two is refused as invalid'
);

select * from finish();
rollback;
