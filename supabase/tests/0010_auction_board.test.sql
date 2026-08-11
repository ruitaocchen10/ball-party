-- Tests for the auction board and its dealer (migration 0010).
--
-- The headline test is not a unit test. It deals a board and asserts that no
-- client-reachable relation contains its points — read as a participant, under
-- RLS, plus the privilege and publication facts that back that up. That is the
-- failure which would be invisible until somebody noticed the game was broken,
-- which is why it asserts on grants and replication rather than on what a
-- screen shows.

begin;
select plan(37);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m4', tests.deal(4, 0.25));
select tests.act_as_admin();

-- ------------------------------------------------------------- composition --

select is(
  (select count(*)::int from public.auction_lots where match_id = (select v from tests.fx where k = 'm4')),
  20,
  'a four-player board is 5N = 20 lots'
);

select is(
  (select lot_count::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm4')),
  20,
  'and the match row agrees'
);

select is(
  (select array_agg(c order by pos) from (
     select position as pos, count(*)::int as c
       from public.auction_lots
      where match_id = (select v from tests.fx where k = 'm4') and not is_flex
      group by position) x),
  array[4, 4, 4, 4],
  'the base lots are N of each of QB, RB, WR, TE'
);

select is(
  (select count(*)::int from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4') and is_flex),
  4,
  'and there are N flex lots'
);

select ok(
  (select bool_and(position in ('RB','WR','TE')) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4') and is_flex),
  'every flex lot is drawn from {RB, WR, TE}'
);

-- seq is play order, so the flex lots are the last N and nothing earlier is
-- flex. The no-stranding argument depends on this.
select is(
  (select array_agg(seq order by seq) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4') and is_flex),
  array[17, 18, 19, 20]::smallint[],
  'the flex lots are the last N by seq, and no earlier lot is flex'
);

select is(
  (select count(distinct player_id)::int from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4')),
  20,
  'no player appears twice on a board'
);

-- Tier is checked by joining back to the pool, because the lot itself must not
-- carry it — see the leak tests below.
select is(
  (select array_agg(c order by t) from (
     select pw.tier as t, count(*)::int as c
       from public.auction_lots al
       join private.player_weeks pw
         on pw.player_id = al.player_id and pw.season = al.season and pw.week = al.week
      where al.match_id = (select v from tests.fx where k = 'm4')
      group by pw.tier) x),
  array[5, 8, 7],
  'the tier quota at N=4 is 7 star, 8 solid, 5 deep (deep, solid, star alphabetically)'
);

-- ------------------------------------------------- the quota at other sizes --

insert into tests.fx (k, v) values ('m3', tests.deal(3, 0.5));
select tests.act_as_admin();

select is(
  (select array_agg(c order by t) from (
     select pw.tier as t, count(*)::int as c
       from public.auction_lots al
       join private.player_weeks pw
         on pw.player_id = al.player_id and pw.season = al.season and pw.week = al.week
      where al.match_id = (select v from tests.fx where k = 'm3')
      group by pw.tier) x),
  array[4, 6, 5],
  'the quota at N=3 is 5/6/4 — the odd lot goes to the largest remainder, deep'
);

select is(
  (select count(*)::int from public.auction_lots where match_id = (select v from tests.fx where k = 'm3')),
  15,
  'and a three-player board is 15 lots'
);

insert into tests.fx (k, v) values ('m2', tests.deal(2, 0.75));
select tests.act_as_admin();

select is(
  (select array_agg(c order by t) from (
     select pw.tier as t, count(*)::int as c
       from public.auction_lots al
       join private.player_weeks pw
         on pw.player_id = al.player_id and pw.season = al.season and pw.week = al.week
      where al.match_id = (select v from tests.fx where k = 'm2')
      group by pw.tier) x),
  array[2, 4, 4],
  'the quota at N=2 is 4/4/2 — star and deep tie on remainder and star takes it'
);

select is(
  (select count(*)::int from public.auction_lots where match_id = (select v from tests.fx where k = 'm2')),
  10,
  'and a two-player board is 10 lots'
);

-- ------------------------------------------------------------------- seats --

select is(
  (select array_agg(ap.seat order by ap.seat) from public.auction_players ap
    where ap.match_id = (select v from tests.fx where k = 'm4')),
  array[0, 1, 2, 3]::smallint[],
  'every seated player gets an auction_players row'
);

select ok(
  not exists (
    select 1
      from public.auction_players ap
      join public.matches mt on mt.id = ap.match_id
      join public.run_participants rp
        on rp.run_id = mt.run_id and rp.user_id = ap.user_id
     where ap.match_id = (select v from tests.fx where k = 'm4')
       and ap.seat is distinct from rp.seat
  ),
  'seats are copied from run_participants, not shuffled again'
);

select is(
  (select array_agg(distinct budget) from public.auction_players
    where match_id = (select v from tests.fx where k = 'm4')),
  array[20],
  'everyone starts on $20'
);

-- --------------------------------------------------------- reproducibility --

insert into tests.fx (k, v) values ('m4_same', tests.deal(4, 0.25));
insert into tests.fx (k, v) values ('m4_other', tests.deal(4, 0.9));
select tests.act_as_admin();

select is(
  (select array_agg(player_id order by seq) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4_same')),
  (select array_agg(player_id order by seq) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4')),
  'the same seed deals an identical board'
);

select isnt(
  (select array_agg(player_id order by seq) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4_other')),
  (select array_agg(player_id order by seq) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4')),
  'a different seed does not'
);

select is(
  (select seed from private.auction_boards where match_id = (select v from tests.fx where k = 'm4')),
  0.25::double precision,
  'the seed is stored, so a board that played out strangely can be looked at'
);

-- The seed is an answer key: the dealer is in the repository, the tier bands are
-- in the repository, and the source data is public. It gets the same treatment
-- as the points.
select hasnt_column('public', 'auction_matches', 'seed',
  'the seed is not on the client-readable match row');

select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'private' and tablename = 'auction_boards'
  ),
  'and private.auction_boards is in no publication'
);

-- ------------------------------------------------------------ the answers --
--
-- This is the point of the whole module.

select is(
  (select count(*)::int from private.auction_answers where match_id = (select v from tests.fx where k = 'm4')),
  20,
  'every lot has an answer stored'
);

select ok(
  not exists (
    select 1 from public.auction_lots al
      join private.auction_answers aa
        on aa.match_id = al.match_id and aa.seq = al.seq
      join private.player_weeks pw
        on pw.player_id = al.player_id and pw.season = al.season and pw.week = al.week
     where al.match_id = (select v from tests.fx where k = 'm4')
       and aa.points is distinct from pw.points
  ),
  'and it is the real fantasy points for that player-week'
);

select ok(
  (select bool_and(points is null) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4')),
  'no dealt lot carries its points'
);

select ok(
  (select bool_and(winner_id is null and price is null and slot is null and resolved_at is null)
     from public.auction_lots where match_id = (select v from tests.fx where k = 'm4')),
  'and nothing is resolved yet'
);

-- Read as a participant, under RLS, which is the shape a browser actually sees.
select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm4')
   order by rp.seat limit 1
));

select is(
  (select count(*)::int from public.auction_lots where match_id = (select v from tests.fx where k = 'm4')),
  20,
  'a participant can read the board'
);

select ok(
  (select bool_and(points is null) from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm4')),
  'and every points column they can see is null'
);

select throws_ok(
  'select count(*) from private.auction_answers',
  '42501',
  null,
  'and the answers table is not reachable from an authenticated session at all'
);

select tests.act_as_admin();

-- The two facts that back that up, asserted directly because they are what a
-- future migration could widen by accident.
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'private' and table_name = 'auction_answers'
       and grantee in ('anon', 'authenticated', 'PUBLIC')
  ),
  'no client role holds any privilege on private.auction_answers'
);

select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'private' and tablename = 'auction_answers'
  ),
  'and it is in no publication, so Realtime can never replicate it'
);

-- The four client-readable tables are in, since the UI is driven by them.
select bag_eq(
  $$ select tablename::text from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename like 'auction%' $$,
  $$ values ('auction_matches'), ('auction_players'), ('auction_lots'), ('auction_bids') $$,
  'the four client-readable auction tables are replicated'
);

-- No hint of tier or rank crossed over. Easy to add later by accident.
select hasnt_column('public', 'auction_lots', 'tier',
  'a lot does not carry its tier — that would price the card before anyone bid');
select hasnt_column('public', 'auction_lots', 'pos_rank',
  'nor its positional rank');

-- ------------------------------------------------------------- refusals --

-- Constructed, because start_run already refuses a one-person lobby: the
-- platform floor and the game floor are different rules that happen to agree at
-- N=1 today. This asserts the game's own floor exists rather than being assumed.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_thin', tests.mkmatch(2));
select tests.act_as_admin();

delete from public.run_participants
 where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm_thin'))
   and seat = 1;

select throws_ok(
  format($$ select private.deal_auction_board(%L, 0.1) $$, (select v from tests.fx where k = 'm_thin')),
  'P0001', 'too_few_players',
  'a one-player table is refused by the dealer, which is where a game floor belongs'
);

-- start_auction is the real entry point: it checks the caller and the state,
-- and flips the match to playing.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('m_start', tests.mkmatch(4));

select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_start')
   order by rp.seat limit 1
));
select lives_ok(
  format($$ select public.start_auction(%L, 'weekly', 'standard') $$, (select v from tests.fx where k = 'm_start')),
  'a participant can start the auction'
);

select tests.act_as_admin();
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 'm_start')),
  'playing',
  'starting the auction moves the match out of setup'
);

-- Dealing twice is refused, which is the same check.
select tests.act_as((
  select rp.user_id from public.run_participants rp
    join public.matches mt on mt.run_id = rp.run_id
   where mt.id = (select v from tests.fx where k = 'm_start')
   order by rp.seat limit 1
));
select throws_ok(
  format($$ select public.start_auction(%L, 'weekly', 'standard') $$, (select v from tests.fx where k = 'm_start')),
  'P0001', 'match_not_setup',
  'a match that is already playing cannot be dealt again'
);

-- Somebody outside the run cannot start it.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('nosy'));
insert into tests.fx (k, v) values ('m_guard', tests.mkmatch(2));

select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select public.start_auction(%L, 'weekly', 'standard') $$, (select v from tests.fx where k = 'm_guard')),
  '42501', 'not_a_participant',
  'someone who is not in the run cannot start its auction'
);

select * from finish();
rollback;
