begin;
select plan(10);

\ir support/harness.psql

select tests.mkmatch(2) as match_id \gset

select auction.start(:'match_id', 'weekly', 'standard');

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

-- Which of two ways this gets blocked depends on the environment: the
-- hosted project grants public tables to anon and authenticated by default
-- (a local CLI stack no longer does — see 0010's own comment on this), so
-- the write either fails outright on the missing table privilege or is
-- accepted and then filtered to zero rows by RLS, which carries no UPDATE
-- policy for auction_matches. Either way the row must not change, so that's
-- the invariant this asserts rather than which grant a given stack happens
-- to carry.
select format($fmt$
do $$
begin
  update public.auction_matches set roster_preset = 'wide' where match_id = %L;
exception when insufficient_privilege then null;
end $$;
$fmt$, :'match_id') \gexec

select is(
  (select roster_preset from public.auction_matches where match_id = :'match_id'),
  'standard',
  'participants cannot mutate a dealt format directly'
);

select tests.mkmatch(2) as invalid_scoring_match \gset
select throws_ok(
  format($$ select auction.start(%L, 'season', 'standard') $$, :'invalid_scoring_match'),
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
  format($$ select auction.start(%L, 'weekly', 'impossible') $$, :'invalid_roster_match'),
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
  format($$ select auction.start(%L, null, 'standard') $$, :'missing_scoring_match'),
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
