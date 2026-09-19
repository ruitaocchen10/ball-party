-- Tests for per-game resolution (0117): a weekly Picks post grades and reveals
-- each slot as its own game goes final, and only closes once the last slot is
-- graded. Like 0096, drives grade_due_game_picks with fabricated nflverse CSV
-- text rather than the network.

begin;
select plan(21);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('viewer', tests.mkuser('viewer'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$
  select email from auth.users where id = p_id;
$$;

create function tests.act_as_prompts_admin() returns void
language plpgsql as $$
declare
  v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(v_id))::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end $$;

-- Same column order as the real nflverse release, truncated after the columns
-- the grader reads. Thursday's game is final (AWY wins); the tie never has a
-- winner; game-later is unplayed until p_later_final flips it to a HOM win.
create function tests.schedule(p_later_final boolean) returns text
language sql as $$
  select string_agg(line, E'\n') from (values
    ('header,season,game_type,week,gameday,weekday,gametime,away_team,away_score,home_team,home_score,location,result'),
    ('game-thursday,2026,REG,2,2026-09-17,Thursday,20:15,AWY,27,HOM,20,Home,-7'),
    ('game-tie,2026,REG,2,2026-09-20,Sunday,13:00,AWY,24,HOM,24,Home,0'),
    ('game-later,2026,REG,2,2026-09-21,Monday,20:15,AWY,' || case when p_later_final then '10' else '' end
       || ',HOM,' || case when p_later_final then '17' else '' end || ',Home,')
  ) as t(line)
$$;

-- A Picks post with one winner slot per game id, already locked.
create function tests.mk_picks(p_games text[]) returns uuid
language plpgsql as $$
declare
  v_slots jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'label', g, 'shape', 'pick', 'points', 10, 'source_game_id', g,
    'options', jsonb_build_array(
      jsonb_build_object('label', 'Away', 'team_code', 'AWY'),
      jsonb_build_object('label', 'Home', 'team_code', 'HOM')
    )
  ) order by ord)
  into v_slots
  from unnest(p_games) with ordinality as t (g, ord);

  return prompts.create_post(
    'picks', 'Picks', 'cap', 'who wins', 'crit', now() - interval '1 hour', v_slots,
    jsonb_build_object('provider', 'nflverse', 'rule', 'winner')
  );
end $$;

create function tests.slot_of(p_post uuid, p_game text) returns uuid
language sql as $$
  select id from public.prompt_slots where post_id = p_post and source_game_id = p_game
$$;

create function tests.pick(p_post uuid, p_game text, p_team text) returns void
language sql as $$
  insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids)
  select p_post, s.id, (select v from tests.fx where k = 'viewer'),
         array[(select o.id from public.prompt_slot_options o where o.slot_id = s.id and o.team_code = p_team)]
    from public.prompt_slots s where s.post_id = p_post and s.source_game_id = p_game
$$;

create function tests.points(p_post uuid, p_game text) returns smallint
language sql as $$
  select r.points_earned from public.prompt_responses r where r.slot_id = tests.slot_of(p_post, p_game)
$$;

-- ------------------------------------------------------------- fixtures --

select tests.act_as_prompts_admin();
insert into tests.fx (k, v) select 'week', tests.mk_picks(array['game-thursday', 'game-tie', 'game-later']);
insert into tests.fx (k, v) select 'pair', tests.mk_picks(array['game-thursday', 'game-later']);
-- Never in any feed below, so it stays open for the answer-validation guard.
insert into tests.fx (k, v) select 'unlisted', tests.mk_picks(array['game-unlisted']);

select tests.act_as_admin();
select tests.pick((select v from tests.fx where k = 'week'), 'game-thursday', 'AWY');
select tests.pick((select v from tests.fx where k = 'week'), 'game-later', 'AWY');
select tests.pick((select v from tests.fx where k = 'pair'), 'game-thursday', 'HOM');
select tests.pick((select v from tests.fx where k = 'pair'), 'game-later', 'HOM');

-- ------------------------------------------- Thursday final, rest pending --

select prompts_private.grade_due_game_picks(tests.schedule(false));

select is(
  (select so.team_code from public.prompt_slots sl
     join public.prompt_slot_options so on so.id = any (sl.correct_option_ids)
    where sl.id = tests.slot_of((select v from tests.fx where k = 'week'), 'game-thursday')),
  'AWY', 'the finished Thursday slot is graded and revealed on its own');
select is(
  (select correct_option_ids from public.prompt_slots
    where id = tests.slot_of((select v from tests.fx where k = 'week'), 'game-later')),
  null, 'a slot whose game has no score yet stays unrevealed');
select is(
  (select correct_option_ids from public.prompt_slots
    where id = tests.slot_of((select v from tests.fx where k = 'week'), 'game-tie')),
  null, 'a tied game leaves only its own slot pending');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'week')),
  'open', 'the post stays open while any slot is ungraded — the production bug was the opposite');
select is((select resolved_at from public.prompt_posts where id = (select v from tests.fx where k = 'week')),
  null, 'and resolved_at is still null');
select is(tests.points((select v from tests.fx where k = 'week'), 'game-thursday'),
  10::smallint, 'the viewer is paid for the graded slot straight away (Bills-style: picked the winner)');
select is(tests.points((select v from tests.fx where k = 'pair'), 'game-thursday'),
  0::smallint, 'a wrong pick on a graded slot scores 0');
select is(tests.points((select v from tests.fx where k = 'week'), 'game-later'),
  null, 'an ungraded slot has no points yet');
select is(
  (select count(*)::int from private.prompt_slot_answers
    where slot_id in (select id from public.prompt_slots where post_id = (select v from tests.fx where k = 'week'))),
  1, 'only the graded slot has a stored answer');

-- Re-running the same feed is a no-op: graded slots are not selected again.
select lives_ok($$ select prompts_private.grade_due_game_picks(tests.schedule(false)) $$,
  're-running over a partially graded post does not error');
select is(tests.points((select v from tests.fx where k = 'week'), 'game-thursday'),
  10::smallint, 'and does not change points already awarded');

-- ----------------------------------------------- last game closes the post --

select prompts_private.grade_due_game_picks(tests.schedule(true));

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'pair')),
  'resolved', 'the post resolves once its last slot is graded');
select isnt((select resolved_at from public.prompt_posts where id = (select v from tests.fx where k = 'pair')),
  null, 'and resolved_at is set');
select is(tests.points((select v from tests.fx where k = 'pair'), 'game-later'),
  10::smallint, 'the last slot is scored (HOM won 17-10)');
select is((select sum(points_earned)::int from public.prompt_responses
            where post_id = (select v from tests.fx where k = 'pair')),
  10, 'the post total is the sum of its per-game scores');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'week')),
  'open', 'a post with a tied game never fully resolves on its own — it stays for an admin');

-- ------------------------------------------------------------ admin path --

-- resolve_post over a post the sweep has only partly graded: Thursday's slot
-- grades from the feed, the tie slot can't, so an admin supplies every answer.
select tests.act_as_prompts_admin();
insert into tests.fx (k, v) select 'partial', tests.mk_picks(array['game-thursday', 'game-tie']);
select tests.act_as_admin();
select prompts_private.grade_due_game_picks(tests.schedule(true));

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'partial')),
  'open', 'setup: the Thursday slot graded, the tie slot is pending');

select tests.act_as_prompts_admin();
select lives_ok(
  format($$ select prompts.resolve_post(%L, %L::jsonb) $$,
    (select v from tests.fx where k = 'partial'),
    (select jsonb_object_agg(s.id::text, jsonb_build_array((
       select o.id from public.prompt_slot_options o
        where o.slot_id = s.id and o.team_code = case s.source_game_id when 'game-tie' then 'HOM' else 'AWY' end
     ))) from public.prompt_slots s where s.post_id = (select v from tests.fx where k = 'partial'))),
  'an admin can resolve a post whose slots are partly auto-graded');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'partial')),
  'resolved', 'and the post closes');

-- ---------------------------------------------------------------- guards --

-- An answer must be one of the slot's own options (0098's check, restored).
select tests.act_as_admin();
select throws_ok(
  format($$ select prompts_private.do_resolve_slot(%L, array[%L::uuid]) $$,
    tests.slot_of((select v from tests.fx where k = 'unlisted'), 'game-unlisted'),
    (select o.id from public.prompt_slot_options o
      where o.slot_id = tests.slot_of((select v from tests.fx where k = 'week'), 'game-later') limit 1)),
  '22023', null, 'an option belonging to a different slot is rejected as an answer');

-- prompts_private isn't reachable from a signed-in session at all.
select tests.act_as((select v from tests.fx where k = 'admin'));
select throws_ok(
  format($$ select prompts_private.do_resolve_slot(%L, array[]::uuid[]) $$,
    tests.slot_of((select v from tests.fx where k = 'week'), 'game-later')),
  '42501', null, 'do_resolve_slot has no grant for authenticated');

select * from finish();
rollback;
