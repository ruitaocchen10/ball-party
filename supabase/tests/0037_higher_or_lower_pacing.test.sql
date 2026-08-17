-- Pacing: what ends a question, and who the question is still waiting for.
--
-- The three behaviours here are one transition, so they are asserted as one
-- match played question by question rather than as three isolated fixtures.
-- The order matters: a player is present, then silent, then latched absent,
-- then back — and each step changes what the next question does.
begin;
select plan(18);
\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.mkmatch(3, 'higher_or_lower'));
select tests.act_as((select user_id from public.run_participants where run_id = (
  select run_id from public.matches where id = (select v from tests.fx where k = 'm')
) order by seat limit 1));
select higher_or_lower.start((select v from tests.fx where k = 'm'));

select tests.act_as_admin();
insert into tests.fx (k, v)
select 'one', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm') order by seat limit 1;
insert into tests.fx (k, v)
select 'two', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'three', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm') order by seat offset 2 limit 1;
select tests.open_question((select v from tests.fx where k = 'm'), 1::smallint);

-- ------------------------------------------------- question one: early advance

-- Three ticks, so all three are present for what follows. Presence is the
-- input to early advance, and a board dealt a moment ago has nobody on it who
-- has said anything yet.
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'three'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));

select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 1::smallint));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'call', 'one call of three leaves the question open');

-- Scoring is a reveal-time event, not a call-time one. A streak that moved the
-- instant a call landed would tell its owner the answer — and, through the
-- published players row, tell everyone who could already read the direction.
select tests.act_as_admin();
select is((select current_streak from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'one')),
  0, 'a call on its own moves no streak, so the answer stays behind the reveal');

select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 1::smallint));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'call', 'and the last outstanding present player still holds it open');

select tests.act_as((select v from tests.fx where k = 'three'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 1::smallint));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'reveal', 'the last present caller ends the question in their own transaction');
select tests.act_as_admin();
select ok((select points is not null and revealed_at is not null from public.higher_or_lower_cards
  where match_id = (select v from tests.fx where k = 'm') and ordinal = 1),
  'and that transition reveals the card, exactly as an expired deadline would');
select is((select array[current_streak, best_streak, correct_count] from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'one')),
  array[1, 1, 1], 'a correct call is scored when the question reveals');

-- -------------------------------------------------- question two: the timeout

select tests.hol_expire((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'three'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));

-- Two calls, one silence. Three is present — they ticked this question — so
-- the question runs to its deadline rather than advancing on two of three.
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 2::smallint));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'm'), 2::smallint));

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm'));
select ok((select direction is null and timed_out from public.higher_or_lower_calls
  where match_id = (select v from tests.fx where k = 'm') and question = 2
    and user_id = (select v from tests.fx where k = 'three')),
  'the reveal records the silent player as a flagged miss');
select is((select timed_out from public.higher_or_lower_calls
  where match_id = (select v from tests.fx where k = 'm') and question = 2
    and user_id = (select v from tests.fx where k = 'two')),
  false, 'and leaves a wrong call unflagged, so the UI can tell the two apart');

-- The whole point of one scoring path: these two players did different things
-- and the counters cannot tell them apart.
select is(
  (select array[current_streak, best_streak, correct_count] from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'three')),
  (select array[current_streak, best_streak, correct_count] from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'two')),
  'a miss moves the same three counters a wrong call moves');
select is((select array[current_streak, best_streak, correct_count] from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'two')),
  array[0, 1, 1], 'and both end the current streak while the best one stands');

-- ------------------------------------------------ question three: going quiet

select tests.hol_expire((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));

-- Every now() inside one pgTAP transaction is the same instant, so a player who
-- stops ticking looks identical to one who just ticked. This says the thing the
-- server would have observed on its own — three's last sign of life predates
-- this question — the same way the suites above force a deadline into the past.
select tests.act_as_admin();
update public.higher_or_lower_players set last_seen_at = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm')
   and user_id = (select v from tests.fx where k = 'three');

-- Three says nothing at all this question. They are not absent yet: absence is
-- judged over a whole question, so this is the question that judges it.
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 3::smallint));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 3::smallint));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'call', 'a player who has gone quiet is still waited for during the question');

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm'));
select is((select absent from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'three')),
  true, 'a whole silent question latches them absent at the reveal');
select is((select array[best_streak, correct_count] from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'three')),
  array[1, 1], 'their earlier work survives going away');

-- ---------------------------------------- question four: not waiting for them

select tests.hol_expire((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 4::smallint));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 4::smallint));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'reveal', 'a departed player costs the table one question, not every question');

-- ------------------------------------------- question five: coming back again

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm'));
update public.higher_or_lower_players set last_seen_at = now() - interval '1 hour'
 where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'three');

select tests.act_as((select v from tests.fx where k = 'three'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select tests.act_as_admin();
select ok((select last_seen_at > now() - interval '1 minute' from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'three')),
  'a tick stamps its caller as last seen now');
select is((select absent from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'three')),
  false, 'and clears the absence it was latched with');

select tests.act_as((select v from tests.fx where k = 'one'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 5::smallint));
select tests.act_as((select v from tests.fx where k = 'two'));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select higher_or_lower.call((select v from tests.fx where k = 'm'),
  tests.hol_answer((select v from tests.fx where k = 'm'), 5::smallint));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'call', 'and puts them back among the players the question waits for');

select tests.act_as((select v from tests.fx where k = 'three'));
select is((select count(*)::int from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm')),
  3, 'nobody is ever removed from the scoreboard by leaving it');

select * from finish();
rollback;
