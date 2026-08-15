-- Calls are server-validated decisions. Their directions are hidden by RLS,
-- while a separate status projection tells every player who has locked in.
begin;
select plan(17);
\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.mkmatch(3, 'higher_or_lower'));
select tests.act_as((select user_id from public.run_participants where run_id = (
  select run_id from public.matches where id = (select v from tests.fx where k = 'm')
) order by seat limit 1));
select higher_or_lower.start((select v from tests.fx where k = 'm'));

-- Put the dealt match at a live question without bypassing the call function's
-- deadline check. The cards' private answers decide correctness below.
select tests.act_as_admin();
update public.higher_or_lower_matches
   set phase = 'call', phase_deadline = now() + interval '1 minute'
 where match_id = (select v from tests.fx where k = 'm');
insert into tests.fx (k, v)
select 'one', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm') order by seat limit 1;
insert into tests.fx (k, v)
select 'two', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'three', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm') order by seat offset 2 limit 1;

select tests.act_as((select v from tests.fx where k = 'one'));
select lives_ok(
  format($$ select higher_or_lower.call(%L, 'higher') $$, (select v from tests.fx where k = 'm')),
  'a participant can call during the live call phase'
);
select is((select direction from public.higher_or_lower_calls where match_id = (select v from tests.fx where k = 'm')
  and user_id = (select v from tests.fx where k = 'one')), 'higher', 'the caller can read their own direction');
select is((select count(*)::int from public.higher_or_lower_call_statuses where match_id = (select v from tests.fx where k = 'm')),
  1, 'the separate presence projection records the lock-in');
select throws_ok(
  format($$ select higher_or_lower.call(%L, 'lower') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'already_called', 'a second call for the same question is rejected'
);

-- Before two has called, status is visible but one's direction is not. This is
-- a policy test, not a client omission test.
select tests.act_as((select v from tests.fx where k = 'two'));
select is((select count(*)::int from public.higher_or_lower_call_statuses where match_id = (select v from tests.fx where k = 'm')),
  1, 'another player can always see who has locked in');
select is((select count(*)::int from public.higher_or_lower_calls where match_id = (select v from tests.fx where k = 'm')),
  0, 'but cannot read their direction before calling');
select lives_ok(
  format($$ select higher_or_lower.call(%L, 'lower') $$, (select v from tests.fx where k = 'm')),
  'a second participant can lock in independently'
);
select is((select count(*)::int from public.higher_or_lower_calls where match_id = (select v from tests.fx where k = 'm')),
  2, 'after calling, the participant can read both directions');

-- The third player has not called, so RLS still hides both calls. Reveal makes
-- them readable to everyone, even without a call of their own.
select tests.act_as((select v from tests.fx where k = 'three'));
select is((select count(*)::int from public.higher_or_lower_calls where match_id = (select v from tests.fx where k = 'm')),
  0, 'an uncalled player still receives no direction rows');
select tests.act_as_admin();
update public.higher_or_lower_cards set points = a.points, revealed_at = now()
  from higher_or_lower_private.answers a
 where higher_or_lower_cards.match_id = a.match_id and higher_or_lower_cards.ordinal = a.ordinal
   and higher_or_lower_cards.match_id = (select v from tests.fx where k = 'm') and higher_or_lower_cards.ordinal = 1;
update public.higher_or_lower_matches set phase = 'reveal' where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'three'));
select is((select count(*)::int from public.higher_or_lower_calls where match_id = (select v from tests.fx where k = 'm')),
  2, 'after reveal every participant can read every direction');

-- The function protects every invalid write boundary, including an expired
-- deadline and someone with no seat in the match.
select tests.act_as_admin();
update public.higher_or_lower_matches set phase = 'call', phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'three'));
select throws_ok(
  format($$ select higher_or_lower.call(%L, 'higher') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'call_deadline_passed', 'a call after its deadline is rejected'
);
select tests.act_as_admin();
update public.higher_or_lower_matches set phase = 'reveal', phase_deadline = now() + interval '1 minute'
 where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'three'));
select throws_ok(
  format($$ select higher_or_lower.call(%L, 'higher') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'call_not_open', 'a call outside its phase is rejected'
);
select tests.act_as_admin();
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));
select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select higher_or_lower.call(%L, 'higher') $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_a_participant', 'a non-participant cannot call'
);

-- Correctness comes from private answers, not public revealed points. Call both
-- directions on question two so the assertions cover extension and reset.
select tests.act_as_admin();
update public.higher_or_lower_matches set current_question = 2, phase = 'call', phase_deadline = now() + interval '1 minute'
 where match_id = (select v from tests.fx where k = 'm');
update public.higher_or_lower_cards set points = a.points, revealed_at = now()
  from higher_or_lower_private.answers a
 where higher_or_lower_cards.match_id = a.match_id and higher_or_lower_cards.ordinal = a.ordinal
   and higher_or_lower_cards.match_id = (select v from tests.fx where k = 'm') and higher_or_lower_cards.ordinal = 2;
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.call((select v from tests.fx where k = 'm'), case when (
  select b.points > a.points from public.higher_or_lower_cards a join public.higher_or_lower_cards b
    on b.match_id = a.match_id and b.ordinal = a.ordinal + 1
   where a.match_id = (select v from tests.fx where k = 'm') and a.ordinal = 1
) then 'higher' else 'lower' end);
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.call((select v from tests.fx where k = 'm'), case when (
  select b.points > a.points from public.higher_or_lower_cards a join public.higher_or_lower_cards b
    on b.match_id = a.match_id and b.ordinal = a.ordinal + 1
   where a.match_id = (select v from tests.fx where k = 'm') and a.ordinal = 1
) then 'lower' else 'higher' end);
select tests.act_as_admin();
select ok((select current_streak >= 1 and best_streak >= current_streak and correct_count >= 1
  from public.higher_or_lower_players where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'one')),
  'a correct call extends current streak, raises best streak, and increments correct count');
select is((select current_streak from public.higher_or_lower_players where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'two')),
  0, 'a wrong call resets current streak without removing the player');
select is((select count(*)::int from public.higher_or_lower_players where match_id = (select v from tests.fx where k = 'm')),
  3, 'all players remain in the match after a wrong call');
select tests.act_as((select v from tests.fx where k = 'three'));
select is((select count(*)::int from public.higher_or_lower_players where match_id = (select v from tests.fx where k = 'm')),
  3, 'every participant can always read the table streak projection');

select * from finish();
rollback;
