-- Scout token (0159): a coarse performance tier for the lot currently
-- showing, revealed only to the player who spent the token for it.
--
-- The leak check is the point of this suite, the same way it was the point
-- of 0010's leak test for `private.auction_answers`: the opponent's own
-- authenticated session has to come back empty, not merely have its UI told
-- not to show the row. If that regresses, it regresses as a silent RLS
-- widening, not as a build failure, which is exactly the failure mode worth
-- a direct assertion.

begin;
select plan(14);

\ir support/harness.psql

-- -------------------------------------------------------- the tier thresholds --
-- Mirrors the boundary tests for weeklyRevealTier in
-- webapp/lib/games/auction/board.test.ts -- these two have to agree, and
-- this is the test that would catch them drifting apart.

select tests.act_as_admin();
select is(auction_private.weekly_tier('QB', 14.9), 'rough', 'QB below 15 is rough');
select is(auction_private.weekly_tier('QB', 15),   'solid', 'QB at 15 is solid');
select is(auction_private.weekly_tier('QB', 25),   'great', 'QB at 25 is great');
select is(auction_private.weekly_tier('TE', 8),    'solid', 'TE uses its own, lower solid threshold');
select is(auction_private.weekly_tier('RB', 10),   'solid', 'RB/WR/FLEX share the default threshold');

-- --------------------------------------------------------- the reveal, and its leak --

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m1', tests.deal_and_open(2, 0.31));
insert into tests.fx (k, v) select 'm1_scout', ap.user_id
  from public.auction_players ap
  join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm1') and ap.seat = am.turn_seat;
insert into tests.fx (k, v) select 'm1_other', ap.user_id
  from public.auction_players ap
  join public.auction_matches am on am.match_id = ap.match_id
 where ap.match_id = (select v from tests.fx where k = 'm1') and ap.seat <> am.turn_seat;

select tests.act_as((select v from tests.fx where k = 'm1_scout'));
select auction.use_scout_token((select v from tests.fx where k = 'm1'));

select tests.act_as_admin();
select is(
  (select tier from public.auction_scouting_hints
    where match_id = (select v from tests.fx where k = 'm1') and seq = 1
      and user_id = (select v from tests.fx where k = 'm1_scout')),
  (select auction_private.weekly_tier(
    (select position from public.auction_lots where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
    (select points from private.auction_answers where match_id = (select v from tests.fx where k = 'm1') and seq = 1)
  )),
  'the written tier matches the engine''s own weekly_tier math for the real card'
);
select is(
  (select used_scout_token from public.auction_players
    where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_scout')),
  true,
  'spends the scouting player''s token'
);
select is(
  (select used_pass_token from public.auction_players
    where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_scout')),
  false,
  'and leaves their other abilities untouched'
);

select tests.act_as((select v from tests.fx where k = 'm1_scout'));
select is(
  (select count(*)::int from public.auction_scouting_hints
    where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  1,
  'the scouting player can read their own hint back'
);

select tests.act_as((select v from tests.fx where k = 'm1_other'));
select is(
  (select count(*)::int from public.auction_scouting_hints
    where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  0,
  'but the opponent''s own session sees nothing at all -- not a hidden value, an absent row'
);

select tests.act_as_admin();
select is(
  (select count(*)::int from public.auction_scouting_hints
    where match_id = (select v from tests.fx where k = 'm1') and seq = 1),
  1,
  'the row genuinely exists -- the opponent''s empty read above is RLS, not a missing write'
);

-- ----------------------------------------------------------------- refusals --

select tests.act_as((select v from tests.fx where k = 'm1_scout'));
select throws_ok(
  format($$ select auction.use_scout_token(%L) $$, (select v from tests.fx where k = 'm1')),
  'P0001', 'no_scout_tokens',
  'a second attempt is refused once the token is already spent'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m2', tests.deal(2, 0.32, 'season_total', 'standard'));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm2');
select auction_private.advance((select v from tests.fx where k = 'm2'));
select tests.act_as((select user_id from public.auction_players where match_id = (select v from tests.fx where k = 'm2') and seat = 0));
select ok(
  auction.use_scout_token((select v from tests.fx where k = 'm2')) in ('rough', 'solid', 'great'),
  'a season-total match scouts too, with a percentile-based tier (0170)'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m3', tests.deal_and_open(2, 0.33));
insert into tests.fx (k, v) select 'm3_winner', ap.user_id
  from public.auction_players ap where ap.match_id = (select v from tests.fx where k = 'm3') and ap.seat = 0;
select auction_private.resolve((select v from tests.fx where k = 'm3'), 1::smallint,
  (select v from tests.fx where k = 'm3_winner'), 0);
select tests.act_as((select v from tests.fx where k = 'm3_winner'));
select throws_ok(
  format($$ select auction.use_scout_token(%L) $$, (select v from tests.fx where k = 'm3')),
  'P0001', 'lot_already_resolved',
  'a sold lot refuses the scout token -- its points are already public'
);

select * from finish();
rollback;
