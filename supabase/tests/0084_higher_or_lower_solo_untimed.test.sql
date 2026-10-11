-- Solo Higher or Lower runs on no clock at all: the player calls whenever
-- ready and taps `higher_or_lower.advance` to move past a reveal. Group play
-- keeps its clock unchanged.
begin;
select plan(12);
\ir support/harness.psql

insert into tests.fx (k, v) values ('ava', tests.mkuser('ava')), ('stranger', tests.mkuser('sten'));

-- ------------------------------------------------------------- solo start --

select tests.act_as((select v from tests.fx where k = 'ava'));
insert into tests.fx (k, v) select 'match', (public.start_solo_run('higher_or_lower')).id;
select higher_or_lower.start((select v from tests.fx where k = 'match'));

select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'match')),
  'call', 'a solo start skips the board intro and opens question one directly');
select is((select phase_deadline from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'match')),
  null, 'question one carries no call deadline');

-- ---------------------------------------------------------- an open call --

select higher_or_lower.call((select v from tests.fx where k = 'match'),
  tests.hol_answer((select v from tests.fx where k = 'match'), 1::smallint));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'match')),
  'reveal', 'a solo call still reveals immediately — there is nobody left to wait on');
select is((select phase_deadline from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'match')),
  null, 'the reveal it lands on carries no auto-advance deadline either');

-- ------------------------------------------------------------ advance on --

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select higher_or_lower.advance(%L) $$, (select v from tests.fx where k = 'match')),
  '42501', 'not_a_participant',
  'a stranger cannot advance someone else''s solo reveal'
);

select tests.act_as((select v from tests.fx where k = 'ava'));
select higher_or_lower.advance((select v from tests.fx where k = 'match'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'match')),
  'call', 'a tap on advance opens question two after a correct reveal');
select is((select current_question from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'match')),
  2::smallint, 'and the ladder moved to question two');

select throws_ok(
  format($$ select higher_or_lower.advance(%L) $$, (select v from tests.fx where k = 'match')),
  'P0001', 'advance_not_open',
  'advance only works from a reveal, not mid-call'
);

-- ----------------------------------------------------- a wrong call ends it --

select higher_or_lower.call((select v from tests.fx where k = 'match'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'match'), 2::smallint));
select higher_or_lower.advance((select v from tests.fx where k = 'match'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'match')),
  'complete', 'advancing past a wrong reveal ends the solo run');

-- --------------------------------------------------- group play is untouched --

insert into tests.fx (k, v) values ('room', tests.mkmatch(2, 'higher_or_lower'));
select tests.act_as((select user_id from public.run_participants where run_id = (
  select run_id from public.matches where id = (select v from tests.fx where k = 'room')
) order by seat limit 1));
select higher_or_lower.start((select v from tests.fx where k = 'room'));

select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'room')),
  'board_intro', 'a group start still opens on the shared board intro');
select ok((select phase_deadline from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'room'))
  between now() + interval '7 seconds' and now() + interval '9 seconds',
  'and still carries its five-second deadline, after the three-second start countdown');

select throws_ok(
  format($$ select higher_or_lower.advance(%L) $$, (select v from tests.fx where k = 'room')),
  'P0001', 'not_solo',
  'advance refuses a group board — it keeps its own clock instead'
);

select * from finish();
rollback;
