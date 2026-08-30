-- Tests for the auction board and its dealer (migration 0010).
--
-- The headline test is not a unit test. It deals a board and asserts that no
-- client-reachable relation contains its points — read as a participant, under
-- RLS, plus the privilege and publication facts that back that up. That is the
-- failure which would be invisible until somebody noticed the game was broken,
-- which is why it asserts on grants and replication rather than on what a
-- screen shows.

begin;
select plan(35);

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

-- Positions are no longer dealt as "N base lots of each, then N flex lots
-- last" (0088). QB stays at exactly N, since it never flexes; RB, WR and TE
-- each carry a share of the N flex slots' worth of slack folded into one
-- shared pool, so which slot a lot ends up filling is decided live rather
-- than by a tag set at deal time. See 0011 for the eligibility rule this buys.
--
-- Since 0089 the split of that shared slack is random rather than a fixed
-- RB-then-WR-then-TE priority (see 0011/0019 for why that mattered), so which
-- of RB/WR/TE gets the extra unit at N=4 is no longer pinned to one position.
-- Sorted rather than position-ordered so the assertion holds either way: QB
-- alone at N, two of RB/WR/TE at their base share, one at base-plus-remainder.
select is(
  (select array_agg(c order by c) from (
     select position as pos, count(*)::int as c
       from public.auction_lots
      where match_id = (select v from tests.fx where k = 'm4')
      group by position) x),
  array[4, 5, 5, 6],
  'QB stays at exactly N; RB, TE and WR share the N flex slots worth of slack, one of them getting the odd unit'
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

-- A 2-player Standard table only has flex_slots*N = 2 units of slack to split
-- across three flex-eligible positions. Since 0089 every one of RB/WR/TE is
-- floored at one spare regardless, which pushes this table's total past the
-- old 5N figure (10 -> 11: two positions get their spare from the ordinary
-- remainder split, the third from the floor). The tier quota below is
-- computed from that corrected total, not the old one.
select is(
  (select array_agg(c order by t) from (
     select pw.tier as t, count(*)::int as c
       from public.auction_lots al
       join private.player_weeks pw
         on pw.player_id = al.player_id and pw.season = al.season and pw.week = al.week
      where al.match_id = (select v from tests.fx where k = 'm2')
      group by pw.tier) x),
  array[3, 4, 4],
  'the quota at N=2 (11 lots, once the flex-buffer floor is applied) is 4/4/3'
);

select is(
  (select count(*)::int from public.auction_lots where match_id = (select v from tests.fx where k = 'm2')),
  11,
  'and a two-player board is 5N+1 = 11 lots -- the floor added the unit flex_slots*N alone could not give every position'
);

-- The actual point of 0089: at this table size the fair split alone still
-- leaves one of RB/WR/TE with zero spares (2 units, 3 positions -- somebody
-- always loses the tiebreak). The floor is what guarantees nobody does,
-- regardless of which position the random split shorted.
select ok(
  (select bool_and(c >= 2) from (
     select count(*)::int as c
       from public.auction_lots
      where match_id = (select v from tests.fx where k = 'm2') and position in ('RB', 'WR', 'TE')
      group by position) x),
  'every one of RB/WR/TE gets at least one spare lot beyond its single natural slot, even though the table''s flex budget could not otherwise stretch to all three'
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
  array[25],
  'everyone starts on the standard $25 purse'
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
  format($$ select auction_private.deal_board(%L, 0.1) $$, (select v from tests.fx where k = 'm_thin')),
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
  format($$ select auction.start(%L, 'weekly', 'standard') $$, (select v from tests.fx where k = 'm_start')),
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
  format($$ select auction.start(%L, 'weekly', 'standard') $$, (select v from tests.fx where k = 'm_start')),
  'P0001', 'match_not_setup',
  'a match that is already playing cannot be dealt again'
);

-- Somebody outside the run cannot start it.
select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('nosy'));
insert into tests.fx (k, v) values ('m_guard', tests.mkmatch(2));

select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select auction.start(%L, 'weekly', 'standard') $$, (select v from tests.fx where k = 'm_guard')),
  '42501', 'not_a_participant',
  'someone who is not in the run cannot start its auction'
);

select * from finish();
rollback;
