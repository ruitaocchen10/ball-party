begin;
select plan(16);

\ir support/harness.psql

-- This suite checks an aggregate cohort, so keep local seed responses out of
-- its fixture. The enclosing transaction always rolls this back.
delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('alpha',   tests.mkuser('Alpha')),
  ('bravo',   tests.mkuser('Bravo')),
  ('charlie', tests.mkuser('Charlie')),
  ('hidden',  tests.mkuser('Hidden')),
  ('thin',    tests.mkuser('Thin')),
  ('nobody',  tests.mkuser('Nobody'));

update public.profiles set rankings_visible = false where id = (select v from tests.fx where k = 'hidden');

-- P1 resolved yesterday, P2 resolved 400 days ago (lifetime only).
insert into public.prompt_posts (
  id, template_kind, template_name, author_id, caption, prompt_text,
  resolution_criteria, lock_at, status, resolved_at
) values
  ('10000000-0000-0000-0000-000000000001', 'game_pick', 'Recent', (select v from tests.fx where k = 'alpha'), 'T', 'T', 'T', now() - interval '2 days',   'resolved', now() - interval '1 day'),
  ('10000000-0000-0000-0000-000000000002', 'game_pick', 'Old',    (select v from tests.fx where k = 'alpha'), 'T', 'T', 'T', now() - interval '401 days', 'resolved', now() - interval '400 days');

insert into public.prompt_slots (id, post_id, label, shape, points) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'A', 'pick', 10),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'B', 'pick', 10),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'C', 'pick', 10),
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', 'D', 'pick', 10),
  ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000002', 'E', 'pick', 10),
  ('20000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000002', 'F', 'pick', 10);

-- Week:     alpha 60, bravo 30, charlie 30 (tie), hidden 90 (opted out),
--           thin 100 from only two picks (below the floor).
-- Lifetime: alpha 60, bravo 60 (30 old), charlie 30.
create function pg_temp.respond(p_user text, p_slot int, p_points int) returns void
language sql as $$
  insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
  select s.post_id, s.id, (select v from tests.fx where k = p_user), array[gen_random_uuid()], p_points
    from public.prompt_slots s
   where s.id = ('20000000-0000-0000-0000-00000000000' || p_slot)::uuid;
$$;

do $$
begin
  perform pg_temp.respond('alpha', 1, 20);
  perform pg_temp.respond('alpha', 2, 20);
  perform pg_temp.respond('alpha', 3, 20);
  perform pg_temp.respond('bravo', 1, 10);
  perform pg_temp.respond('bravo', 2, 10);
  perform pg_temp.respond('bravo', 3, 10);
  perform pg_temp.respond('bravo', 4, 10);
  perform pg_temp.respond('bravo', 5, 10);
  perform pg_temp.respond('bravo', 6, 10);
  perform pg_temp.respond('charlie', 1, 10);
  perform pg_temp.respond('charlie', 2, 10);
  perform pg_temp.respond('charlie', 3, 10);
  perform pg_temp.respond('hidden', 1, 30);
  perform pg_temp.respond('hidden', 2, 30);
  perform pg_temp.respond('hidden', 3, 30);
  perform pg_temp.respond('thin', 1, 50);
  perform pg_temp.respond('thin', 2, 50);
end $$;

select tests.act_as((select v from tests.fx where k = 'charlie'));

-- ------------------------------------------------------------- leaderboard --

select is(
  (select array_agg(display_name order by rank, display_name) from public.ball_knower_leaderboard('week')),
  array['Alpha', 'Bravo', 'Charlie'],
  'the board lists only visible players with enough scored picks'
);
select is(
  (select array_agg(rank order by rank, display_name) from public.ball_knower_leaderboard('week')),
  array[1, 2, 2],
  'tied players share a rank'
);
select is(
  (select array_agg(display_name order by display_name) from public.ball_knower_leaderboard('week') where rank = 2),
  array['Bravo', 'Charlie'],
  'a tie is ordered by display name'
);
select is(
  (select array_agg(display_name order by rank, display_name) from public.ball_knower_leaderboard('lifetime')),
  array['Alpha', 'Bravo', 'Charlie'],
  'lifetime counts posts resolved outside the week window'
);
select is(
  (select array_agg(rank order by rank, display_name) from public.ball_knower_leaderboard('lifetime')),
  array[1, 1, 3],
  'lifetime ranks follow lifetime points, with the gap after a tie'
);
select is(
  (select total_points from public.ball_knower_leaderboard('week') where display_name = 'Bravo'),
  30,
  'the week window excludes older resolved posts from a player''s points'
);
select is(
  (select count(*)::int from public.ball_knower_leaderboard('week', 1)),
  1,
  'p_limit caps the number of rows'
);
select is(
  (select array_agg(display_name order by display_name) from public.ball_knower_leaderboard('week') where is_me),
  array['Charlie'],
  'only the caller''s own row is flagged is_me'
);
select is(
  (select max(ranked_count) from public.ball_knower_leaderboard('week')),
  3,
  'ranked_count is the size of the visible, qualified cohort'
);
select throws_ok(
  $$select * from public.ball_knower_leaderboard('decade')$$,
  '22023',
  'invalid_window',
  'an unknown window is rejected'
);

-- ---------------------------------------------------------------- standing --

select is(
  (select (status, rank, total_points, ranked_count)::text from public.my_ball_knower_standing('week')),
  '(ranked,2,30,3)',
  'a qualified player is ranked with the shared tie rank'
);

select tests.act_as((select v from tests.fx where k = 'hidden'));
select is(
  (select (status, total_points)::text from public.my_ball_knower_standing('week')),
  '(hidden,90)',
  'an opted-out player is told they are hidden and still sees their own points'
);

select tests.act_as((select v from tests.fx where k = 'thin'));
select is(
  (select (status, total_points, scored_picks, min_picks)::text from public.my_ball_knower_standing('week')),
  '(unranked,100,2,3)',
  'a player below the pick floor is unranked, with the floor reported'
);

select tests.act_as((select v from tests.fx where k = 'nobody'));
select is(
  (select (status, total_points, scored_picks)::text from public.my_ball_knower_standing('week')),
  '(unranked,0,0)',
  'a player with no scored picks is unranked at zero'
);

-- --------------------------------------------------------------- privileges --

select tests.act_as_admin();
select ok(
  has_function_privilege('authenticated', 'public.ball_knower_leaderboard(text,integer)', 'execute')
    and not has_function_privilege('anon', 'public.ball_knower_leaderboard(text,integer)', 'execute')
    and has_function_privilege('authenticated', 'public.my_ball_knower_standing(text)', 'execute')
    and not has_function_privilege('anon', 'public.my_ball_knower_standing(text)', 'execute'),
  'only signed-in players can call the leaderboard RPCs'
);
select ok(
  not has_function_privilege('authenticated', 'private.ball_knower_totals(text)', 'execute')
    and not has_function_privilege('authenticated', 'private.ball_knower_cohort(text)', 'execute'),
  'the cohort helpers are not callable by clients'
);

select * from finish();
rollback;
