begin;
select plan(10);

\ir support/harness.psql

select tests.mkmatch(2) as match_id \gset

select public.start_auction(:'match_id', 'weekly', 'standard');

select is(
  (select row(scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse)::text
     from public.auction_matches where match_id = :'match_id'),
  '(weekly,standard,1,1,1,1,1,25)',
  'a newly dealt match snapshots the weekly standard format and its resolved limits and purse'
);

select is(
  (select array_agg(distinct budget order by budget) from public.auction_players where match_id = :'match_id'),
  array[25],
  'the resolved purse is what every player receives'
);

select tests.act_as((
  select rp.user_id from public.run_participants rp
  join public.matches m on m.run_id = rp.run_id
  where m.id = :'match_id' order by rp.seat desc limit 1
));

select is(
  (select roster_preset from public.auction_matches where match_id = :'match_id'),
  'standard',
  'a non-host participant can read the dealt format'
);

select ok(
  not has_table_privilege('authenticated', 'public.auction_matches', 'UPDATE'),
  'participants cannot mutate a dealt format directly'
);

select tests.mkmatch(2) as invalid_scoring_match \gset
select throws_ok(
  format($$ select public.start_auction(%L, 'season', 'standard') $$, :'invalid_scoring_match'),
  'P0001', 'invalid_scoring_mode',
  'an invalid scoring mode is rejected rather than substituted'
);

select is(
  (select status::text from public.matches where id = :'invalid_scoring_match'),
  'setup',
  'a rejected scoring mode leaves the match undealt'
);

select tests.mkmatch(2) as invalid_roster_match \gset
select throws_ok(
  format($$ select public.start_auction(%L, 'weekly', 'impossible') $$, :'invalid_roster_match'),
  'P0001', 'invalid_roster_preset',
  'an invalid roster preset is rejected rather than substituted'
);

select is(
  (select count(*)::int from public.auction_matches where match_id = :'invalid_roster_match'),
  0,
  'a rejected roster preset leaves no partial board'
);

select tests.mkmatch(2) as missing_scoring_match \gset
select throws_ok(
  format($$ select public.start_auction(%L, null, 'standard') $$, :'missing_scoring_match'),
  'P0001', 'invalid_scoring_mode',
  'a missing scoring mode is rejected with the format validation error'
);

select is(
  (select count(*)::int from public.auction_matches where match_id = :'missing_scoring_match'),
  0,
  'a missing configuration cannot create a partial board'
);

select * from finish();
rollback;
