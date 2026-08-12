begin;
select plan(3);

\ir support/harness.psql

-- 0013 shipped the portrait band without a suite, so when 0018 rewrote the
-- dealer and dropped the column from the insert, nothing failed. These are the
-- assertions that would have caught it, and they are per-mode because the two
-- branches select their card fields separately -- one could lose the copy
-- while the other kept it.
select tests.deal(4, 0.37, 'weekly', 'standard') as weekly \gset
select tests.act_as_admin();
select is(
  (select count(*)::int from public.auction_lots where match_id = :'weekly' and headshot_url is null),
  0,
  'every lot on a weekly board carries the headshot for its player'
);

select tests.deal(4, 0.37, 'season_total', 'standard') as season \gset
select tests.act_as_admin();
select is(
  (select count(*)::int from public.auction_lots where match_id = :'season' and headshot_url is null),
  0,
  'every lot on a season board carries the headshot for its player'
);

-- The URL has to belong to the player on the card. A dealer that copied the
-- wrong row would still pass the two counts above.
select is(
  (select count(*)::int from public.auction_lots l
     join private.player_headshots h on h.player_id = l.player_id
    where l.match_id = :'weekly' and l.headshot_url is distinct from h.headshot_url),
  0,
  'each lot carries its own player''s headshot rather than some other row''s'
);

select * from finish();
rollback;
