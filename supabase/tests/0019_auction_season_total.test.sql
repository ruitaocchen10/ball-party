begin;
select plan(15);

\ir support/harness.psql

select tests.mkmatch(2) as match_id \gset
select auction.start(:'match_id', 'season_total', 'standard');

select is(
  (select scoring_mode from public.auction_matches where match_id = :'match_id'),
  'season_total',
  'a host can deal a season-total auction'
);

select ok(
  (select bool_and(week is null and opponent is null) from public.auction_lots where match_id = :'match_id'),
  'season lots omit weekly-only card fields'
);

-- A 2-player Standard table's flex budget (flex_slots*N = 2) can't stretch to
-- cover all three flex-eligible positions; every one of RB/WR/TE is floored
-- at two spares regardless (0090), so this table deals well past the old 5N
-- figure. See 0010 for the fuller explanation.
select is(
  (select count(*)::int from public.auction_lots where match_id = :'match_id'),
  14,
  'the season dealer retains the 5N (plus the flex-buffer floor) board size'
);

select is(
  (select count(*)::int from public.auction_lots where match_id = :'match_id'),
  (select count(*)::int from (select distinct player_id from public.auction_lots where match_id = :'match_id') people),
  'a season board offers each player once, in one season and no other'
);

select tests.act_as_admin();

select is(
  (select array_agg(c order by tier) from (
    select ps.tier, count(*)::int as c
      from public.auction_lots al
      join private.player_seasons ps using (player_id, season)
     where al.match_id = :'match_id'
     group by ps.tier
  ) tiers),
  array[3, 6, 5],
  'the season dealer preserves the tier quota at two players (14 lots, once the flex-buffer floor is applied)'
);

select ok(
  not exists (
    select 1 from public.auction_lots al
    where al.match_id = :'match_id' and al.points is not null
  ),
  'season totals are absent from public lots before resolution'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'private.player_seasons'::regclass)
  and not has_table_privilege('authenticated', 'private.player_seasons', 'SELECT'),
  'the SQL-derived season pool has the weekly answer boundary: RLS and no client select privilege'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'auction_private.deal_board(uuid, double precision, text, text, smallint, smallint)',
    'EXECUTE'
  ),
  'a participant cannot replay a season deal from its private seed boundary'
);

select tests.act_as((
  select rp.user_id from public.run_participants rp
  join public.matches m on m.run_id = rp.run_id
  where m.id = :'match_id' order by rp.seat limit 1
));

select is(
  (select points from public.auction_lots where match_id = :'match_id' and seq = 1),
  null,
  'a participant cannot obtain the season answer through page data before it is won'
);

select tests.act_as_admin();
select auction_private.resolve(
  :'match_id'::uuid, 1::smallint,
  (select user_id from public.auction_players where match_id = :'match_id' order by seat limit 1),
  3
);

select is(
  (select points from public.auction_lots where match_id = :'match_id' and seq = 1),
  (select points from private.auction_answers where match_id = :'match_id' and seq = 1),
  'the season total reveals exactly when its lot resolves'
);

select is(
  (select sum(pw.points) from private.player_weeks pw
   join public.auction_lots al on al.player_id = pw.player_id and al.season = pw.season
   where al.match_id = :'match_id' and al.seq = 1),
  (select points from public.auction_lots where match_id = :'match_id' and seq = 1),
  'the revealed answer equals the aggregate of its player weeks'
);

select tests.mkmatch(2) as complete_match \gset
select tests.act_as_admin();
select auction_private.deal_board(:'complete_match', 0.61, 'season_total', 'standard');
update public.matches set status = 'playing', started_at = now() where id = :'complete_match';
select auction_private.advance(:'complete_match');
select tests.play_out(:'complete_match', 'pass');

select is(
  (select raw_score from public.match_players mp
   where mp.match_id = :'complete_match'
     and mp.user_id = (select winner_id from public.auction_lots where match_id = :'complete_match' and seq = 1)),
  (select sum(points) from public.auction_lots
   where match_id = :'complete_match'
     and winner_id = (select winner_id from public.auction_lots where match_id = :'complete_match' and seq = 1)),
  'final standings aggregate each winner’s revealed season totals'
);

delete from private.player_seasons where position = 'QB' and tier = 'star';
select tests.mkmatch(2) as exhausted_match \gset
-- auction.start deliberately takes no seed (see 0030), so it draws its own
-- from session randomness. Pinned here rather than left to chance: this
-- exact deal needs a QB-star draw, which is the one now-exhausted pairing.
-- Re-pinned for 0090 (was 0.01): deal_board's larger flex buffer consumes a
-- different amount of random() before reaching QB's own draw, which shifts
-- which implicit seed still lands on a QB-star combination.
select setseed(0.02);
select throws_ok(
  format($$ select auction.start(%L, 'season_total', 'standard') $$, :'exhausted_match'),
  'P0001', 'pool_exhausted',
  'a season deal fails loudly when its private pool cannot satisfy a required draw'
);

select tests.mkmatch(2) as invalid_match \gset
select throws_ok(
  format($$ select auction.start(%L, 'season', 'standard') $$, :'invalid_match'),
  'P0001', 'invalid_scoring_mode',
  'an unknown scoring mode fails loudly'
);

select is(
  (select count(*)::int from public.auction_matches where match_id = :'invalid_match'),
  0,
  'a rejected scoring mode leaves no partial board'
);

select * from finish();
rollback;
