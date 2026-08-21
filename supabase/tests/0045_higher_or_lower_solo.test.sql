-- Tests for solo play, Higher or Lower's side (migration 0045). See issue #32.
--
-- Two things: the dealer accepts a one-player table and records that the
-- match it dealt was solo; and a solo player's own game tables — not just the
-- platform's four (0044) — are readable through the private.is_match_member
-- rewrite, the same as any lobby-backed match's are.

begin;
select plan(10);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')), ('stranger', tests.mkuser('sten'));

-- --------------------------------------------------------------- the deal --

insert into tests.fx (k, v)
select 'solo', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'a'), 0.3);

select tests.act_as_admin();

select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'solo')),
  13,
  'a one-player table deals the seed anchor and twelve-question opening ladder'
);

select is(
  (select count(*)::int from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'solo')),
  1,
  'and seats exactly the one player'
);

select is(
  (select is_solo from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'solo')),
  true,
  'the match records that it was dealt solo'
);

-- The lobby-backed path, so is_solo is a fact about the roster this match was
-- actually dealt from and not just a default nobody ever flips back off.
insert into tests.fx (k, v)
select 'group', tests.deal_higher_or_lower(2, 0.3);

select tests.act_as_admin();
select is(
  (select is_solo from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'group')),
  false,
  'a lobby-backed table is not recorded as solo'
);

-- ---------------------------------------------------------------------- RLS --

-- private.is_match_member (0044) is what these three policies are built on;
-- this is the game-specific proof that the platform-level rewrite actually
-- reaches this game's tables rather than only the four generic ones 0044
-- tests directly.
select tests.act_as((select v from tests.fx where k = 'a'));

select is(
  (select count(*)::int from public.higher_or_lower_matches
    where match_id = (select v from tests.fx where k = 'solo')),
  1, 'the solo player can read their own higher_or_lower_matches row'
);
select is(
  (select count(*)::int from public.higher_or_lower_cards
    where match_id = (select v from tests.fx where k = 'solo')),
  13, 'and every card of their own opening ladder'
);
select is(
  (select count(*)::int from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'solo')),
  1, 'and their own seat'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));

select is_empty(
  format($$ select 1 from public.higher_or_lower_matches where match_id = %L $$,
         (select v from tests.fx where k = 'solo')),
  'a different signed-in user cannot read someone else''s solo higher_or_lower_matches row'
);
select is_empty(
  format($$ select 1 from public.higher_or_lower_cards where match_id = %L $$,
         (select v from tests.fx where k = 'solo')),
  'nor a single card of it'
);
select is_empty(
  format($$ select 1 from public.higher_or_lower_players where match_id = %L $$,
         (select v from tests.fx where k = 'solo')),
  'nor its seat'
);

select * from finish();
rollback;
