-- Endless solo Higher or Lower (issue #33).
begin;
select plan(8);
\ir support/harness.psql

insert into tests.fx (k, v) values ('ava', tests.mkuser('ava'));
insert into tests.fx (k, v)
select 'solo', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'ava'), 0.3);
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'solo');

-- A correct twelfth answer extends the ladder with ordinal 13 and opens it.
select tests.open_question((select v from tests.fx where k = 'solo'), 12::smallint);
select tests.act_as((select v from tests.fx where k = 'ava'));
select higher_or_lower.call((select v from tests.fx where k = 'solo'),
  tests.hol_answer((select v from tests.fx where k = 'solo'), 12::smallint));
select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'solo'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'solo')),
  'call', 'a correct call past question twelve opens another solo question');
select is((select current_question from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'solo')),
  13::smallint, 'the continuation is question thirteen');
select is((select count(*)::int from public.higher_or_lower_cards where match_id = (select v from tests.fx where k = 'solo')),
  14, 'the continuation appends one card after the solo opening ladder');
select ok((select abs(challenger.quantile - anchor.quantile) between b.band_min and b.band_max
  from higher_or_lower_private.answers anchor
  join higher_or_lower_private.answers challenger on challenger.match_id = anchor.match_id and challenger.ordinal = 13
  cross join higher_or_lower_private.band(13) b
  where anchor.match_id = (select v from tests.fx where k = 'solo') and anchor.ordinal = 12),
  'the appended card uses question thirteen''s difficulty band');

-- A wrong call ends a solo match immediately at a non-final index.
insert into tests.fx (k, v) select 'miss', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'ava'), 0.4);
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'miss');
select tests.open_question((select v from tests.fx where k = 'miss'), 5::smallint);
select tests.act_as((select v from tests.fx where k = 'ava'));
select higher_or_lower.call((select v from tests.fx where k = 'miss'), tests.hol_wrong_answer((select v from tests.fx where k = 'miss'), 5::smallint));
select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'miss'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'miss')),
  'complete', 'a wrong solo call completes the match at question five');

-- A missed call is also a break, including after the original twelfth question.
insert into tests.fx (k, v) select 'timeout', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'ava'), 0.5);
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'timeout');
select tests.open_question((select v from tests.fx where k = 'timeout'), 12::smallint);
select tests.hol_expire((select v from tests.fx where k = 'timeout'));
select tests.hol_expire((select v from tests.fx where k = 'timeout'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'timeout')),
  'complete', 'a timed-out solo call completes the match at question twelve');

-- An empty eligible deck is an ordinary ending after a correct answer.
insert into tests.fx (k, v) select 'exhausted', tests.deal_solo_higher_or_lower((select v from tests.fx where k = 'ava'), 0.6);
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'exhausted');
select tests.open_question((select v from tests.fx where k = 'exhausted'), 12::smallint);
select tests.act_as((select v from tests.fx where k = 'ava'));
select higher_or_lower.call((select v from tests.fx where k = 'exhausted'),
  tests.hol_answer((select v from tests.fx where k = 'exhausted'), 12::smallint));
select tests.act_as_admin();
delete from private.player_seasons;
select tests.hol_expire((select v from tests.fx where k = 'exhausted'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'exhausted')),
  'complete', 'deck exhaustion completes a solo match without an error');
select is((select count(*)::int from public.match_players where match_id = (select v from tests.fx where k = 'exhausted')),
  1, 'deck exhaustion still writes the solo standing');

select * from finish();
rollback;
