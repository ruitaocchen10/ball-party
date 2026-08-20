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

select is(
  (select count(*)::int from public.auction_lots where match_id = :'match_id'),
  10,
  'the season dealer retains the 5N board size'
);

select is(
  (select count(*)::int from public.auction_lots where match_id = :'match_id'),
  (select count(*)::int from (select distinct player_id from public.auction_lots where match_id = :'match_id') people),
  'a season board offers each player once, in one season and no other'
);

select tests.act_as_admin();

select is(
  (select array_agg(c order by tier) from (
    with ranked_deck as (
      select ps.player_id, ps.season,
             ntile(20) over (partition by ps.position order by ps.points desc, ps.player_id, ps.season) as quantile
        from private.player_seasons ps
    )
    select case when quantile <= 7 then 'star' when quantile <= 15 then 'solid' else 'deep' end as tier, count(*)::int as c
      from public.auction_lots al
      join ranked_deck d using (player_id, season)
     where al.match_id = :'match_id'
     group by tier
  ) tiers),
  array[2, 4, 4],
  'the season dealer preserves the selected-deck band quota at two players'
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

delete from private.player_seasons where position = 'QB';
select tests.mkmatch(2) as exhausted_match \gset
select throws_ok(
  format($$ select auction.start(%L, 'season_total', 'standard') $$, :'exhausted_match'),
  'P0001', 'pool_exhausted',
  'a season deal fails loudly when its selected private deck cannot satisfy a required draw'
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
