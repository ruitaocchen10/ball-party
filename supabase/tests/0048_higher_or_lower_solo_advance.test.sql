-- Solo Higher or Lower keeps going past a correct early answer (issue #33
-- follow-up). 0046's own test only ever exercised a correct call at question
-- twelve, which is the one ordinal `extend_board` can append without
-- colliding with the pre-dealt ladder -- see 0048.
begin;
select plan(3);
\ir support/harness.psql

insert into tests.fx (k, v) values ('ava', tests.mkuser('ava'));
insert into tests.fx (k, v)
select 'solo', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'ava'), 0.3);
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'solo');

-- A correct first answer must open question two, not stall reveal forever by
-- trying (and failing) to re-deal the second ordinal `deal_board` already dealt.
select tests.open_question((select v from tests.fx where k = 'solo'), 1::smallint);
select tests.act_as((select v from tests.fx where k = 'ava'));
select higher_or_lower.call((select v from tests.fx where k = 'solo'),
  tests.hol_answer((select v from tests.fx where k = 'solo'), 1::smallint));
select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'solo'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'solo')),
  'call', 'a correct first answer opens question two instead of stalling in reveal');
select is((select current_question from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'solo')),
  2::smallint, 'the ladder advances to question two');
select is((select count(*)::int from public.higher_or_lower_cards where match_id = (select v from tests.fx where k = 'solo')),
  13, 'question two reuses the card 0046 already pre-dealt rather than appending one');

select * from finish();
rollback;
