begin;
select plan(14);
\ir support/harness.psql

-- ------------------------------------------------------------ what it deals --

select tests.mkmatch(4) as modern_match \gset
select auction.start(:'modern_match', 'weekly', 'standard', 2020::smallint, 2025::smallint);

select is(
  (select row(season_from, season_to)::text from public.auction_matches where match_id = :'modern_match'),
  '(2020,2025)',
  'the chosen era is snapshotted onto the match beside the rest of the format'
);

select ok(
  (select bool_and(season between 2020 and 2025) from public.auction_lots where match_id = :'modern_match'),
  'every lot on the board comes from inside the chosen era'
);

-- Narrowing must not disturb the quota, because tier is a per-season finish.
select is(
  (select count(*)::int from public.auction_lots where match_id = :'modern_match'),
  20,
  'a narrowed era deals the same number of lots'
);

select tests.mkmatch(4) as season_match \gset
select auction.start(:'season_match', 'season_total', 'standard', 2010::smallint, 2015::smallint);
select ok(
  (select bool_and(season between 2010 and 2015) from public.auction_lots where match_id = :'season_match'),
  'the era applies to the season-total pool as well as the weekly one'
);

-- ------------------------------------------------------------- what it refuses --

select tests.mkmatch(2) as inverted_match \gset
select throws_ok(
  format($$ select auction.start(%L, 'weekly', 'standard', 2025::smallint, 2020::smallint) $$, :'inverted_match'),
  'P0001', 'invalid_season_range',
  'a range that runs backwards is rejected rather than reordered'
);

select tests.mkmatch(2) as narrow_match \gset
select throws_ok(
  format($$ select auction.start(%L, 'weekly', 'standard', 2023::smallint, 2025::smallint) $$, :'narrow_match'),
  'P0001', 'season_range_too_narrow',
  'a range under the minimum span is rejected rather than widened'
);

select is(
  (select count(*)::int from public.auction_matches where match_id = :'narrow_match'),
  0,
  'a rejected era leaves no partial board'
);

select is(
  (select status::text from public.matches where id = :'narrow_match'),
  'setup',
  'a rejected era leaves the match undealt'
);

select tests.mkmatch(2) as outside_match \gset
select throws_ok(
  format($$ select auction.start(%L, 'weekly', 'standard', 2005::smallint, 2025::smallint) $$, :'outside_match'),
  'P0001', 'season_out_of_range',
  'an era reaching outside the pool is rejected rather than clipped to it'
);

-- ------------------------------------------------------------- what it defaults --

select tests.mkmatch(2) as default_match \gset
select auction.start(:'default_match', 'weekly', 'standard');

select is(
  (select row(season_from, season_to)::text from public.auction_matches where match_id = :'default_match'),
  (select format('(%s,%s)', season_min, season_max) from auction.season_bounds()),
  'omitting the era resolves to the whole pool and is recorded, not left null'
);

-- --------------------------------------------------------------- the bounds --

select is(
  (select min_span from auction.season_bounds()),
  4::smallint,
  'the host is told the same minimum span the dealer enforces'
);

-- Reading the pool directly to check the answer needs the owner; the assertion
-- above already proved a player can call the function.
select tests.act_as_admin();
select is(
  (select row(season_min, season_max)::text from auction.season_bounds()),
  (select format('(%s,%s)', min(season), max(season)) from private.player_weeks),
  'the offered bounds are read from the pool rather than written down'
);

-- The pool itself stays unreachable; only its extent is published.
select ok(
  not has_table_privilege('authenticated', 'private.player_weeks', 'SELECT'),
  'publishing the era bounds does not publish the pool behind them'
);

-- --------------------------------------------------------------- the replay --

select tests.act_as_admin();
select private.finish_match(:'modern_match', (
  select jsonb_object_agg(user_id::text, 1) from public.run_participants
   where run_id = (select run_id from public.matches where id = :'modern_match')
));

select tests.act_as((
  select l.host_id from public.lobbies l
  join public.runs r on r.lobby_id = l.id
  join public.matches m on m.run_id = r.id
  where m.id = :'modern_match'
));
select next_match_id as replay_match
  from public.choose_post_game(:'modern_match', 'replay'::public.post_game_choice) \gset

select is(
  (select row(season_from, season_to)::text from public.auction_matches where match_id = :'replay_match'),
  '(2020,2025)',
  'a replay deals from the era the first board was dealt from'
);

select * from finish();
rollback;
