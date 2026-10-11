-- Tests for the Wavelength schema, its dealer, and its two entry points
-- (migration 0161, issue #97).
--
-- The deal tests pin a seed through wavelength_private.deal_board, the way
-- every other game's suite does, because the public entry point deliberately
-- takes none. The entry-point tests then go through wavelength.start as real
-- players. The hidden tables are default-deny in this slice; #98 adds their
-- psychic-only policies and owns the focused leak test in 0162.
--
-- The helpers below live in this file rather than in support/harness.psql: they
-- are this suite's convenience, not a shared fixture.

begin;
select plan(71);

\ir support/harness.psql

-- The nth seated player of a match, by seat (1-based).
create function tests.wl_member(p_match uuid, p_i int) returns uuid
language sql stable security definer as $$
  select rp.user_id
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match
   order by rp.seat
  offset p_i - 1 limit 1;
$$;

-- A fresh match of p_n players in the given game, dealt through the pinned
-- dealer (not start), left acting as admin.
create function tests.wl_deal(p_n int, p_mode text, p_preset text, p_seed double precision, out match_id uuid)
returns uuid language plpgsql as $$
begin
  match_id := tests.mkmatch(p_n, 'wavelength_2v2');
  perform tests.act_as_admin();
  perform wavelength_private.deal_board(match_id, p_mode, p_preset, p_seed);
end $$;

insert into tests.fx (k, v) values ('v',  tests.wl_deal(4, 'versus', null,     0.25));
insert into tests.fx (k, v) values ('v2', tests.wl_deal(4, 'versus', null,     0.25));
insert into tests.fx (k, v) values ('cs', tests.wl_deal(2, 'coop',   'short',  0.25));
insert into tests.fx (k, v) values ('cm', tests.wl_deal(2, 'coop',   'medium', 0.25));
insert into tests.fx (k, v) values ('cl', tests.wl_deal(2, 'coop',   'long',   0.25));
select tests.act_as_admin();

-- ------------------------------------------------------------------ privilege --

select ok(
  not has_schema_privilege('authenticated', 'wavelength_private', 'usage'),
  'the rules engine and deck are unreachable by a signed-in player'
);
select ok(
  not has_schema_privilege('anon', 'wavelength_private', 'usage'),
  'and by a signed-out one'
);
select ok(
  has_schema_privilege('authenticated', 'wavelength', 'usage'),
  'the write API schema is reachable'
);
select ok(
  not has_function_privilege('authenticated', 'wavelength_private.deal_board(uuid,text,text,double precision)', 'execute'),
  'the dealer, which takes a seed, is not callable by a client'
);

-- -------------------------------------------------------------------- config --

select is(
  wavelength_private.config() - 'presets',
  '{"scale_max":1000,"wedge_width":40,"clue_max_words":8,"clue_max_chars":100,
    "fill_seconds_per_clue":90,"guess_seconds":60,"versus_rounds":8}'::jsonb,
  'config holds every scalar tunable the design doc names'
);
select is(
  wavelength_private.config() -> 'presets',
  '{"short":{"rounds":4,"target":8,"star2":12,"star3":15},
    "medium":{"rounds":6,"target":12,"star2":18,"star3":22},
    "long":{"rounds":8,"target":20,"star2":24,"star3":29}}'::jsonb,
  'and the three co-op presets with their targets and star thresholds'
);
select ok(
  (wavelength_private.config() ->> 'wedge_width')::int * 5 <= (wavelength_private.config() ->> 'scale_max')::int,
  'the five-wedge scoring zone fits on the line'
);

-- ---------------------------------------------------------------------- deck --

select is(
  (select count(*)::int from wavelength_private.deck),
  68,
  'the deck holds the 68 approved cards'
);
select is(
  (select row(left_label, right_label)::text from wavelength_private.deck where card_id = 1),
  '("Overrated QB","Underrated QB")',
  'a card carries the number it had in the review file, and both endpoints'
);
select is(
  (select left_label from wavelength_private.deck where card_id = 4),
  'Player you''d never party with',
  'an apostrophe survives the seed'
);
select is(
  (select count(*)::int from wavelength_private.deck where card_id in (2, 36, 43, 60, 125)),
  0,
  'cards rejected in review are not in the deck'
);

-- ------------------------------------------------------------------ the versus deal --

select is(
  (select count(*)::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v')),
  8,
  'a versus match is eight rounds'
);
select is(
  (select count(distinct card_id)::int from public.wavelength_cards where match_id = (select v from tests.fx where k = 'v')),
  8,
  'with eight different cards, none repeated'
);
select is(
  (select count(*)::int from public.wavelength_targets where match_id = (select v from tests.fx where k = 'v')),
  8,
  'and a hidden target for each'
);
select ok(
  (select min(target) >= 100 and max(target) <= 900
     from public.wavelength_targets where match_id = (select v from tests.fx where k = 'v')),
  'every target is centred so the whole scoring zone fits on the line'
);
select is(
  (select array_agg(n order by team) from (
     select team, count(*)::int n from public.wavelength_players
      where match_id = (select v from tests.fx where k = 'v') group by team) s),
  array[2, 2],
  'the four players split into two teams of two'
);
select is(
  (select count(*)::int from (
     select psychic_id from public.wavelength_rounds
      where match_id = (select v from tests.fx where k = 'v')
      group by psychic_id having count(*) = 2) s),
  4,
  'each of the four players is the psychic exactly twice'
);
select ok(
  not exists (
    select 1
      from public.wavelength_rounds r
      join public.wavelength_players p on p.match_id = r.match_id and p.user_id = r.psychic_id
      join public.wavelength_players g on g.match_id = r.match_id and g.user_id = r.guesser_id
     where r.match_id = (select v from tests.fx where k = 'v') and p.team <> g.team
  ),
  'the guesser is always the psychic''s teammate'
);
select ok(
  not exists (
    select 1
      from public.wavelength_rounds r1
      join public.wavelength_players p1 on p1.match_id = r1.match_id and p1.user_id = r1.psychic_id
      join public.wavelength_rounds r2 on r2.match_id = r1.match_id and r2.round = r1.round + 1
      join public.wavelength_players p2 on p2.match_id = r2.match_id and p2.user_id = r2.psychic_id
     where r1.match_id = (select v from tests.fx where k = 'v') and p1.team = p2.team
  ),
  'the psychic''s team alternates every round'
);
select is(
  (select mode from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')),
  'versus', 'the match records its mode'
);
select ok(
  (select preset is null from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')),
  'a versus match has no preset'
);
select is(
  (select round_count::int from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')),
  8, 'and records eight rounds'
);
select is(
  (select current_round::int from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')),
  1, 'it starts on round one'
);
select is(
  (select phase from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')),
  'fill', 'in the fill phase'
);
select ok(
  (select phase_deadline = now() + interval '180 seconds'
     from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')),
  'the fill clock is 90 seconds for each of the two clues a player writes'
);
select ok(
  not exists (
    select 1
      from public.wavelength_players wp
      join public.matches mt on mt.id = wp.match_id
      join public.run_participants rp on rp.run_id = mt.run_id and rp.user_id = wp.user_id
     where wp.match_id = (select v from tests.fx where k = 'v') and wp.seat is distinct from rp.seat
  ),
  'seats are copied from run_participants, not shuffled again'
);
select ok(
  not exists (
    select 1
      from public.wavelength_cards c
      join wavelength_private.deck d on d.card_id = c.card_id
     where c.match_id = (select v from tests.fx where k = 'v')
       and (c.left_label <> d.left_label or c.right_label <> d.right_label)
  ),
  'a round''s card carries the deck''s labels'
);
select is(
  (select array_agg(card_id order by round) from public.wavelength_cards where match_id = (select v from tests.fx where k = 'v')),
  (select array_agg(card_id order by round) from public.wavelength_cards where match_id = (select v from tests.fx where k = 'v2')),
  'the same seed deals the same cards'
);
select is(
  (select array_agg(target order by round) from public.wavelength_targets where match_id = (select v from tests.fx where k = 'v')),
  (select array_agg(target order by round) from public.wavelength_targets where match_id = (select v from tests.fx where k = 'v2')),
  'and the same targets'
);

-- --------------------------------------------------------------- the co-op deal --

select is(
  (select array_agg(round_count::int order by round_count) from public.wavelength_matches
    where match_id in (select v from tests.fx where k in ('cs', 'cm', 'cl'))),
  array[4, 6, 8],
  'co-op rounds follow the preset: 4, 6 and 8'
);
select is(
  (select array_agg(preset order by round_count) from public.wavelength_matches
    where match_id in (select v from tests.fx where k in ('cs', 'cm', 'cl'))),
  array['short', 'medium', 'long'],
  'and the match records which preset'
);
select is(
  (select count(distinct team)::int from public.wavelength_players
    where match_id = (select v from tests.fx where k = 'cs')),
  1,
  'both co-op players are on one team'
);
select is(
  (select team::int from public.wavelength_players where match_id = (select v from tests.fx where k = 'cs') limit 1),
  0,
  'team 0'
);
select is(
  (select array_agg(n) from (
     select count(*)::int n from public.wavelength_rounds
      where match_id = (select v from tests.fx where k = 'cl') group by psychic_id) s),
  array[4, 4],
  'each co-op player is the psychic for half the rounds (4 of 8 on Long)'
);
select ok(
  not exists (
    select 1
      from public.wavelength_rounds r1
      join public.wavelength_rounds r2 on r2.match_id = r1.match_id and r2.round = r1.round + 1
     where r1.match_id = (select v from tests.fx where k = 'cl') and r1.psychic_id = r2.psychic_id
  ),
  'and they alternate every round'
);
select ok(
  not exists (
    select 1 from public.wavelength_rounds
     where match_id in (select v from tests.fx where k in ('cs', 'cm', 'cl')) and psychic_id = guesser_id
  ),
  'the guesser is always the other player'
);
select is(
  (select array_agg(extract(epoch from phase_deadline - now())::int order by round_count)
     from public.wavelength_matches where match_id in (select v from tests.fx where k in ('cs', 'cm', 'cl'))),
  array[180, 270, 360],
  'the fill clock scales with how many clues each player writes (2, 3 and 4)'
);
select is(
  (select count(distinct card_id)::int from public.wavelength_cards where match_id = (select v from tests.fx where k = 'cl')),
  8,
  'a Long co-op match is eight distinct cards'
);

-- ----------------------------------------------------------------- the schema --

select throws_ok(
  $$ with r as (
       insert into public.wavelength_rounds (match_id, round, psychic_id, guesser_id)
       select match_id, 9, psychic_id, guesser_id from public.wavelength_rounds
        where match_id = (select v from tests.fx where k = 'v') and round = 1
       returning match_id)
     insert into public.wavelength_cards (match_id, round, card_id, left_label, right_label)
     select r.match_id, 9, c.card_id, c.left_label, c.right_label
       from r join public.wavelength_cards c on c.match_id = r.match_id and c.round = 1 $$,
  '23505',
  null,
  'the schema itself refuses a card twice in one match'
);
select throws_ok(
  $$ insert into public.wavelength_matches (match_id, mode, preset, round_count)
     select id, 'coop', null, 4 from public.matches where game = 'wavelength_2v2' limit 1 $$,
  '23514',
  null,
  'a co-op match without a preset violates the schema'
);
select throws_ok(
  $$ insert into public.wavelength_matches (match_id, mode, preset, round_count)
     select id, 'versus', 'short', 8 from public.matches where game = 'wavelength_2v2' limit 1 $$,
  '23514',
  null,
  'and so does a versus match with one'
);

-- ------------------------------------------------------------ the entry points --

insert into tests.fx (k, v) values ('s4', tests.mkmatch(4, 'wavelength_2v2'));
insert into tests.fx (k, v) values ('s2', tests.mkmatch(2, 'wavelength_2v2'));
insert into tests.fx (k, v) values ('s3', tests.mkmatch(3, 'wavelength_2v2'));
insert into tests.fx (k, v) values ('hol', tests.mkmatch(4, 'higher_or_lower'));
select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));

select throws_ok(
  format($$ select wavelength.start(%L, 'versus') $$, (select v from tests.fx where k = 's4')),
  '42501', 'not_authenticated',
  'without a session there is no identity to start as'
);

select tests.act_as(tests.wl_member((select v from tests.fx where k = 's4'), 2));

select is(
  (select phase from wavelength.start((select v from tests.fx where k = 's4'), 'versus')),
  'fill',
  'a participant can start a four-player versus match, and it opens in fill'
);
select tests.act_as_admin();
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 's4')),
  'playing',
  'and the platform match is now playing'
);
select is(
  (select count(*)::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 's4')),
  8,
  'start dealt the whole board'
);

select tests.act_as(tests.wl_member((select v from tests.fx where k = 's4'), 1));
select throws_ok(
  format($$ select wavelength.start(%L, 'versus') $$, (select v from tests.fx where k = 's4')),
  'P0001', 'match_not_setup',
  'a match cannot be dealt twice'
);
select is(
  (select mode from wavelength.state((select v from tests.fx where k = 's4'))),
  'versus',
  'any participant can read the board back'
);
select is(
  (select current_round::int from wavelength.state((select v from tests.fx where k = 's4'))),
  1,
  'including which round it is on'
);

select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select wavelength.state(%L) $$, (select v from tests.fx where k = 's4')),
  '42501', 'not_a_participant',
  'a non-participant cannot read the board'
);
select throws_ok(
  format($$ select wavelength.start(%L, 'versus') $$, (select v from tests.fx where k = 's2')),
  '42501', 'not_a_participant',
  'or start someone else''s match'
);

select tests.act_as(tests.wl_member((select v from tests.fx where k = 's2'), 1));
select throws_ok(
  format($$ select wavelength.start(%L, 'versus') $$, (select v from tests.fx where k = 's2')),
  'P0001', 'player_count_mismatch',
  'versus needs four players: two is refused'
);
select throws_ok(
  format($$ select wavelength.start(%L, 'coop') $$, (select v from tests.fx where k = 's2')),
  'P0001', 'invalid_preset',
  'co-op without a preset is refused'
);
select throws_ok(
  format($$ select wavelength.start(%L, 'coop', 'huge') $$, (select v from tests.fx where k = 's2')),
  'P0001', 'invalid_preset',
  'as is a preset that does not exist'
);
select throws_ok(
  format($$ select wavelength.start(%L, 'solo') $$, (select v from tests.fx where k = 's2')),
  'P0001', 'invalid_mode',
  'an unknown mode is refused'
);
select throws_ok(
  format($$ select wavelength.start(%L, null) $$, (select v from tests.fx where k = 's2')),
  'P0001', 'invalid_mode',
  'and so is none'
);

select tests.act_as(tests.wl_member((select v from tests.fx where k = 's3'), 1));
select throws_ok(
  format($$ select wavelength.start(%L, 'versus') $$, (select v from tests.fx where k = 's3')),
  'P0001', 'player_count_mismatch',
  'a lobby of three cannot start versus'
);
select throws_ok(
  format($$ select wavelength.start(%L, 'coop', 'short') $$, (select v from tests.fx where k = 's3')),
  'P0001', 'player_count_mismatch',
  'or co-op'
);

select tests.act_as(tests.wl_member((select v from tests.fx where k = 'hol'), 1));
select throws_ok(
  format($$ select wavelength.start(%L, 'versus') $$, (select v from tests.fx where k = 'hol')),
  'P0001', 'wrong_game',
  'a match of another game is refused'
);
select throws_ok(
  $$ select wavelength.start(gen_random_uuid(), 'versus') $$,
  'P0001', 'match_not_found',
  'and so is one that does not exist'
);

-- A rejected deal must leave the match exactly as it was.
select tests.act_as_admin();
select is(
  (select status::text from public.matches where id = (select v from tests.fx where k = 's3')),
  'setup',
  'a refused start leaves the match in setup'
);
select is(
  (select count(*)::int from public.wavelength_matches where match_id = (select v from tests.fx where k = 's3')),
  0,
  'and dealt nothing'
);

select tests.act_as(tests.wl_member((select v from tests.fx where k = 's2'), 1));
select is(
  (select preset from wavelength.start((select v from tests.fx where k = 's2'), 'coop', 'short')),
  'short',
  'a two-player lobby starts co-op with a preset'
);

-- ------------------------------------------------------- the hidden tables --
--
-- Their owner-only access is exercised in 0162. This schema suite retains the
-- invariants that remain true after that slice: the deck is unreachable, the
-- public round metadata is readable to members, and clients cannot write it.

select tests.act_as(tests.wl_member((select v from tests.fx where k = 's4'), 1));

select throws_ok(
  $$ select count(*) from wavelength_private.deck $$,
  '42501', 'permission denied for schema wavelength_private',
  'or the deck'
);
select is(
  (select count(*)::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 's4')),
  8,
  'but can read the rounds of their own match'
);
select throws_ok(
  $$ insert into public.wavelength_rounds (match_id, round, psychic_id, guesser_id)
     select match_id, 99, psychic_id, guesser_id from public.wavelength_rounds limit 1 $$,
  '42501', 'permission denied for table wavelength_rounds',
  'and cannot write to them'
);

select tests.act_as((select v from tests.fx where k = 'outsider'));
select is(
  (select count(*)::int from public.wavelength_rounds),
  0,
  'a non-participant reads no rounds'
);
select is(
  (select count(*)::int from public.wavelength_players),
  0,
  'no players'
);
select is(
  (select count(*)::int from public.wavelength_matches),
  0,
  'and no matches'
);

select tests.act_as_admin();

select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'supabase_realtime'
      and tablename in ('wavelength_matches', 'wavelength_players', 'wavelength_rounds',
                        'wavelength_clue_statuses', 'wavelength_results')),
  5,
  'the five tables with nothing hidden are in the Realtime publication'
);
select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename in ('wavelength_cards', 'wavelength_targets')),
  0,
  'and the two hidden ones are in no publication'
);
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute
    where attrelid = 'wavelength.board'::regclass and attnum > 0 and not attisdropped),
  array['match_id', 'mode', 'preset', 'round_count', 'current_round', 'phase', 'phase_deadline', 'server_now', 'team_scores'],
  'the board projection carries no hidden value, only public team totals'
);

select * from finish();
rollback;
