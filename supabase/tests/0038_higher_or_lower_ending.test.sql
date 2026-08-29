-- The ending: an exact tie on total correct and best streak enters sudden
-- death, and every way sudden death can end lands in the standings the
-- platform already reads.
--
-- Reaching the twelfth question's reveal for real is #25/#26/#27's job and
-- their own suites already cover it question by question. This suite starts
-- each scenario there directly — best_streak and correct_count set by hand,
-- the match parked in 'reveal' at question twelve with its deadline in the
-- past — the same shortcut 0033 and 0037 take with phase_deadline, so what is
-- under test here is what happens at and after that reveal, not how a match
-- arrives at it.
begin;
select plan(40);
\ir support/harness.psql

-- ---------------------------------------------------- a single top streak --

insert into tests.fx (k, v) values ('m1', tests.deal_higher_or_lower(3, 0.15));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'm1_a', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm1') order by seat limit 1;
insert into tests.fx (k, v)
select 'm1_b', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm1') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'm1_c', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm1') order by seat offset 2 limit 1;

update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm1');
update public.higher_or_lower_players set best_streak = 6, correct_count = 8
 where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_a');
update public.higher_or_lower_players set best_streak = 3, correct_count = 4
 where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_b');
update public.higher_or_lower_players set best_streak = 2, correct_count = 3
 where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_c');
update public.higher_or_lower_matches
   set phase = 'reveal', current_question = 12, phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm1');

select higher_or_lower_private.expire((select v from tests.fx where k = 'm1'));

select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm1')),
  'complete', 'a single top total-correct score completes without a detour through sudden death');
select is((select status::text from public.matches where id = (select v from tests.fx where k = 'm1')),
  'complete', 'and the match itself is marked complete');
select ok(not exists (
    select 1 from public.higher_or_lower_players
     where match_id = (select v from tests.fx where k = 'm1') and sudden_death
  ), 'nobody was ever admitted to sudden death');
select is(
  (select array_agg(user_id order by placement, user_id) from public.match_players
    where match_id = (select v from tests.fx where k = 'm1') and placement = 1),
  array[(select v from tests.fx where k = 'm1_a')],
  'the sole top total-correct score is placed first, on its own');
select is(
  (select array[raw_score] from public.match_players
    where match_id = (select v from tests.fx where k = 'm1') and user_id = (select v from tests.fx where k = 'm1_a')),
  array['8.006'::numeric], 'and standings preserve total correct while encoding the best streak as its tiebreak');

-- ------------------------------------- a tie of two, resolved in one round --

insert into tests.fx (k, v) values ('m2', tests.deal_higher_or_lower(3, 0.35));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'm2_a', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm2') order by seat limit 1;
insert into tests.fx (k, v)
select 'm2_b', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm2') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'm2_c', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm2') order by seat offset 2 limit 1;

update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm2');
update public.higher_or_lower_players set best_streak = 5
 where match_id = (select v from tests.fx where k = 'm2')
   and user_id in ((select v from tests.fx where k = 'm2_a'), (select v from tests.fx where k = 'm2_b'));
update public.higher_or_lower_players set best_streak = 1
 where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_c');
update public.higher_or_lower_matches
   set phase = 'reveal', current_question = 12, phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm2');

select higher_or_lower_private.expire((select v from tests.fx where k = 'm2'));

select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm2')),
  'sudden_death_call', 'an exact tie on total correct and best streak opens sudden death instead');
select is((select current_question from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm2')),
  13::smallint, 'drawing the first spare card as the next question in the same chain');
select ok((select phase_deadline from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm2'))
  between now() + interval '7 seconds' and now() + interval '9 seconds',
  'on a shorter, eight-second timer');
select is(
  (select array_agg(user_id order by user_id) from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm2') and sudden_death),
  (select array_agg(u order by u) from unnest(array[
    (select v from tests.fx where k = 'm2_a'), (select v from tests.fx where k = 'm2_b')
  ]) u),
  'exactly the tied pair is admitted');
select ok(
  not (select sudden_death from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_c')),
  'and the player who was not tied is not');

-- A watcher may not call, admitted or not — sudden death has not started for
-- them and never will.
select tests.act_as((select v from tests.fx where k = 'm2_c'));
select throws_ok(
  format($$ select higher_or_lower.call(%L, 'higher') $$, (select v from tests.fx where k = 'm2')),
  '42501', 'not_alive_in_sudden_death', 'a player who was never tied cannot call in sudden death'
);

select tests.act_as((select v from tests.fx where k = 'm2_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm2'),
  tests.hol_answer((select v from tests.fx where k = 'm2'), 13::smallint));
select tests.act_as((select v from tests.fx where k = 'm2_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm2'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'm2'), 13::smallint));

select tests.act_as_admin();
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm2')),
  'sudden_death_reveal', 'the last admitted caller ends the round early, in their own transaction');
select is((select eliminated_at from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_b')),
  13::smallint, 'the wrong call is eliminated on the round it was wrong');
select is((select eliminated_at from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_a')),
  null, 'the correct call survives');

-- The counters on screen are not frozen at question twelve — a sudden-death
-- round is scored by the same rule every other question is.
select is(
  (select array[current_streak, best_streak, correct_count] from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_a')),
  array[1, 5, 1], 'a correct sudden-death call still moves current streak and correct count');
select is(
  (select array[current_streak, correct_count] from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_b')),
  array[0, 0], 'and a wrong one still resets the current streak, exactly as question twelve would have');

select tests.hol_expire((select v from tests.fx where k = 'm2'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm2')),
  'complete', 'sudden death ends the instant one player is left');
select is(
  (select placement::int from public.match_players
    where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_a')),
  1, 'the survivor is placed first');
select is(
  (select array[
    (select placement::int from public.match_players where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_b')),
    (select placement::int from public.match_players where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_c'))
  ]),
  array[2, 3], 'the eliminated finalist still outranks the player who was never tied');
select is(
  (select raw_score from public.match_players
    where match_id = (select v from tests.fx where k = 'm2') and user_id = (select v from tests.fx where k = 'm2_a')),
  999::numeric,
  'the standings encode sudden-death placement on its own terms, not as a multiple of a best streak that kept moving');

-- A player admitted and then eliminated may not call again either.
select tests.act_as((select v from tests.fx where k = 'm2_b'));
select throws_ok(
  format($$ select higher_or_lower.call(%L, 'higher') $$, (select v from tests.fx where k = 'm2')),
  'P0001', 'match_not_playing', 'a finished match takes no more calls at all'
);

-- --------------------------------------- a three-way tie, and a no-op round --

insert into tests.fx (k, v) values ('m3', tests.deal_higher_or_lower(3, 0.55));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'm3_a', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm3') order by seat limit 1;
insert into tests.fx (k, v)
select 'm3_b', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm3') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'm3_c', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm3') order by seat offset 2 limit 1;

update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm3');
update public.higher_or_lower_players set best_streak = 4
 where match_id = (select v from tests.fx where k = 'm3');
update public.higher_or_lower_matches
   set phase = 'reveal', current_question = 12, phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm3');
select higher_or_lower_private.expire((select v from tests.fx where k = 'm3'));

-- Round thirteen: everybody wrong. Eliminating "everybody" is exactly the
-- no-op guard, so nothing about the field should move.
select tests.act_as((select v from tests.fx where k = 'm3_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'm3'), 13::smallint));
select tests.act_as((select v from tests.fx where k = 'm3_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'm3'), 13::smallint));
select tests.act_as((select v from tests.fx where k = 'm3_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'm3'), 13::smallint));

select tests.act_as_admin();
select ok(
  (select bool_and(eliminated_at is null) from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm3')),
  'a round where every alive player is wrong eliminates nobody');

select tests.hol_expire((select v from tests.fx where k = 'm3'));
select is((select current_question from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm3')),
  14::smallint, 'and the board still deals the next spare');

-- Round fourteen: one wrong, two right. The field actually shrinks this time.
select tests.act_as((select v from tests.fx where k = 'm3_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_answer((select v from tests.fx where k = 'm3'), 14::smallint));
select tests.act_as((select v from tests.fx where k = 'm3_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'm3'), 14::smallint));
select tests.act_as((select v from tests.fx where k = 'm3_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_answer((select v from tests.fx where k = 'm3'), 14::smallint));

select tests.act_as_admin();
select is((select eliminated_at from public.higher_or_lower_players
  where match_id = (select v from tests.fx where k = 'm3') and user_id = (select v from tests.fx where k = 'm3_b')),
  14::smallint, 'the lone wrong call this round is eliminated');

-- Round fifteen: the last two split, so the match resolves to one survivor.
select tests.hol_expire((select v from tests.fx where k = 'm3'));
select tests.act_as((select v from tests.fx where k = 'm3_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_answer((select v from tests.fx where k = 'm3'), 15::smallint));
select tests.act_as((select v from tests.fx where k = 'm3_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm3'),
  tests.hol_wrong_answer((select v from tests.fx where k = 'm3'), 15::smallint));

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm3'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm3')),
  'complete', 'the field narrows to one across rounds and ends there');
select is(
  (select array[
    (select placement::int from public.match_players where match_id = (select v from tests.fx where k = 'm3') and user_id = (select v from tests.fx where k = 'm3_a')),
    (select placement::int from public.match_players where match_id = (select v from tests.fx where k = 'm3') and user_id = (select v from tests.fx where k = 'm3_c')),
    (select placement::int from public.match_players where match_id = (select v from tests.fx where k = 'm3') and user_id = (select v from tests.fx where k = 'm3_b'))
  ]),
  array[1, 2, 3], 'placement follows how many rounds each player survived');

-- ------------------------------------------- exhausted spares, and a fallback --

insert into tests.fx (k, v) values ('m4', tests.deal_higher_or_lower(4, 0.75));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'm4_a', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm4') order by seat limit 1;
insert into tests.fx (k, v)
select 'm4_b', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm4') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'm4_c', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm4') order by seat offset 2 limit 1;
insert into tests.fx (k, v)
select 'm4_d', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm4') order by seat offset 3 limit 1;

update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm4');
update public.higher_or_lower_players set best_streak = 5, correct_count = 8
 where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_a');
update public.higher_or_lower_players set best_streak = 5, correct_count = 8
 where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_b');
update public.higher_or_lower_players set best_streak = 5, correct_count = 8
 where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_c');
update public.higher_or_lower_players set best_streak = 1, correct_count = 1
 where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_d');
update public.higher_or_lower_matches
   set phase = 'reveal', current_question = 12, phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm4');
select higher_or_lower_private.expire((select v from tests.fx where k = 'm4'));

-- All three tied leaders call correctly every round: never a mix, so every
-- round is a no-op and all three ride out every spare the board has. Five
-- spares is exactly the five-round cap, so this scenario tests both at once.
select tests.act_as((select v from tests.fx where k = 'm4_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 13::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 13::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 13::smallint));

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm4'));
select tests.act_as((select v from tests.fx where k = 'm4_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 14::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 14::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 14::smallint));

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm4'));
select tests.act_as((select v from tests.fx where k = 'm4_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 15::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 15::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 15::smallint));

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm4'));
select tests.act_as((select v from tests.fx where k = 'm4_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 16::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 16::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 16::smallint));

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm4'));
select is((select current_question from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm4')),
  17::smallint, 'the fifth and final spare is dealt');

select tests.act_as((select v from tests.fx where k = 'm4_a'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 17::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_b'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 17::smallint));
select tests.act_as((select v from tests.fx where k = 'm4_c'));
select higher_or_lower.call((select v from tests.fx where k = 'm4'),
  tests.hol_answer((select v from tests.fx where k = 'm4'), 17::smallint));

select tests.act_as_admin();
select tests.hol_expire((select v from tests.fx where k = 'm4'));

select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm4')),
  'complete', 'exhausting the spares ends the match even with the field unresolved');
select ok(
  (select bool_and(eliminated_at is null) from public.higher_or_lower_players
    where match_id = (select v from tests.fx where k = 'm4')
      and user_id in (
        (select v from tests.fx where k = 'm4_a'), (select v from tests.fx where k = 'm4_b'),
        (select v from tests.fx where k = 'm4_c')
      )),
  'nobody in an unbroken tie was ever eliminated');
select is(
  (select placement::int from public.match_players
    where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_a')),
  1, 'an exhausted exact tie keeps its shared first placement');
select is(
  (select array[
    (select placement::int from public.match_players where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_b')),
    (select placement::int from public.match_players where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_c'))
  ]),
  array[1, 1], 'every player still tied after the spares shares first rather than inventing a winner');
select is(
  (select placement::int from public.match_players
    where match_id = (select v from tests.fx where k = 'm4') and user_id = (select v from tests.fx where k = 'm4_d')),
  4, 'the player who was never tied still places behind the whole admitted field');

-- ---------------------- tied total correct, resolved by the best streak --

insert into tests.fx (k, v) values ('m5', tests.deal_higher_or_lower(3, 0.95));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'm5_a', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm5') order by seat limit 1;
insert into tests.fx (k, v)
select 'm5_b', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm5') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'm5_c', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm5') order by seat offset 2 limit 1;

update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm5');
update public.higher_or_lower_players set best_streak = 5, correct_count = 8
 where match_id = (select v from tests.fx where k = 'm5') and user_id = (select v from tests.fx where k = 'm5_a');
update public.higher_or_lower_players set best_streak = 4, correct_count = 8
 where match_id = (select v from tests.fx where k = 'm5') and user_id = (select v from tests.fx where k = 'm5_b');
update public.higher_or_lower_players set best_streak = 1, correct_count = 7
 where match_id = (select v from tests.fx where k = 'm5') and user_id = (select v from tests.fx where k = 'm5_c');
update public.higher_or_lower_matches
   set phase = 'reveal', current_question = 12, phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm5');

select higher_or_lower_private.expire((select v from tests.fx where k = 'm5'));

select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm5')),
  'complete', 'a tied top total-correct score resolves without sudden death when best streak differs');
select ok(not exists (
  select 1 from public.higher_or_lower_players
   where match_id = (select v from tests.fx where k = 'm5') and sudden_death
), 'the best-streak tiebreak admits nobody to sudden death');
select is(
  (select placement::int from public.match_players
    where match_id = (select v from tests.fx where k = 'm5') and user_id = (select v from tests.fx where k = 'm5_a')),
  1, 'the longer best streak wins the tied total-correct score');
select is(
  (select placement::int from public.match_players
    where match_id = (select v from tests.fx where k = 'm5') and user_id = (select v from tests.fx where k = 'm5_b')),
  2, 'the shorter-streak player ranks next, ahead of a lower total-correct score');

-- ------------------ more correct answers beat a longer streak outright --

insert into tests.fx (k, v) values ('m6', tests.deal_higher_or_lower(3, 0.85));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'm6_a', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm6') order by seat limit 1;
insert into tests.fx (k, v)
select 'm6_b', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm6') order by seat offset 1 limit 1;
insert into tests.fx (k, v)
select 'm6_c', user_id from public.higher_or_lower_players
 where match_id = (select v from tests.fx where k = 'm6') order by seat offset 2 limit 1;

update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm6');
update public.higher_or_lower_players set best_streak = 6, correct_count = 7
 where match_id = (select v from tests.fx where k = 'm6') and user_id = (select v from tests.fx where k = 'm6_a');
update public.higher_or_lower_players set best_streak = 3, correct_count = 8
 where match_id = (select v from tests.fx where k = 'm6') and user_id = (select v from tests.fx where k = 'm6_b');
update public.higher_or_lower_players set best_streak = 5, correct_count = 2
 where match_id = (select v from tests.fx where k = 'm6') and user_id = (select v from tests.fx where k = 'm6_c');
update public.higher_or_lower_matches
   set phase = 'reveal', current_question = 12, phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm6');

select higher_or_lower_private.expire((select v from tests.fx where k = 'm6'));

select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm6')),
  'complete', 'more total correct answers end the match without sudden death');
select ok(not exists (
  select 1 from public.higher_or_lower_players
   where match_id = (select v from tests.fx where k = 'm6') and sudden_death
), 'a lower best streak cannot send a unique correct-answer leader to sudden death');
select is(
  (select placement::int from public.match_players
    where match_id = (select v from tests.fx where k = 'm6') and user_id = (select v from tests.fx where k = 'm6_b')),
  1, 'more correct answers beat a longer best streak');
select is(
  (select placement::int from public.match_players
    where match_id = (select v from tests.fx where k = 'm6') and user_id = (select v from tests.fx where k = 'm6_a')),
  2, 'the longer streak ranks second when it has fewer correct answers');

select * from finish();
rollback;
