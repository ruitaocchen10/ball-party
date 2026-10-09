begin;
select plan(13);

\ir support/harness.psql

-- Aggregate cohort checks: keep local seed responses out of the fixture.
delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('me',       tests.mkuser('FlMe')),
  ('f1',       tests.mkuser('FlFirst')),
  ('f2',       tests.mkuser('FlSecond')),
  ('thin',     tests.mkuser('FlThin')),
  ('stranger', tests.mkuser('FlStranger')),
  ('lonely',   tests.mkuser('FlLonely')),
  ('guest',    tests.mkguest('FlGuest'));

-- me is friends with f1, f2 and thin. f1 is private (still ranks).
select tests.act_as((select v from tests.fx where k = 'f1'));
select public.set_profile_private(true);
select public.send_friend_request('FlMe');
select tests.act_as((select v from tests.fx where k = 'f2'));
select public.send_friend_request('FlMe');
select tests.act_as((select v from tests.fx where k = 'thin'));
select public.send_friend_request('FlMe');
select tests.act_as((select v from tests.fx where k = 'me'));
select public.accept_friend_request((select v from tests.fx where k = 'f1'));
select public.accept_friend_request((select v from tests.fx where k = 'f2'));
select public.accept_friend_request((select v from tests.fx where k = 'thin'));

select tests.act_as_admin();
insert into public.prompt_posts (id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, status, resolved_at)
values ('10000000-0000-0000-0000-000000000001', 'game_pick', 'T', (select v from tests.fx where k = 'me'), 'T', 'T', 'T', now() - interval '2 days', 'resolved', now() - interval '1 day');
insert into public.prompt_slots (id, post_id, label, shape, points) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'A', 'pick', 10),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'B', 'pick', 10),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'C', 'pick', 10);

-- Week: stranger 90, f1 60, me 30, f2 15, thin 100 from two picks (floor).
create function pg_temp.respond(p_user text, p_slot int, p_points int) returns void
language sql as $$
  insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
  select s.post_id, s.id, (select v from tests.fx where k = p_user), array[gen_random_uuid()], p_points
    from public.prompt_slots s
   where s.id = ('20000000-0000-0000-0000-00000000000' || p_slot)::uuid;
$$;
do $$
declare i int;
begin
  for i in 1..3 loop
    perform pg_temp.respond('stranger', i, 30);
    perform pg_temp.respond('f1', i, 20);
    perform pg_temp.respond('me', i, 10);
    perform pg_temp.respond('f2', i, 5);
    perform pg_temp.respond('lonely', i, 40);
  end loop;
  perform pg_temp.respond('thin', 1, 50);
  perform pg_temp.respond('thin', 2, 50);
end $$;

select tests.act_as((select v from tests.fx where k = 'me'));

select is(
  (select array_agg(display_name order by rank) from public.ball_knower_leaderboard('week', 50, 'friends')),
  array['FlFirst', 'FlMe', 'FlSecond'],
  'the friends board is the caller plus friends over the pick floor, private friends included'
);
select is(
  (select array_agg(rank order by rank) from public.ball_knower_leaderboard('week', 50, 'friends')),
  array[1, 2, 3],
  'friends ranks are relative to the friends cohort'
);
select is(
  (select max(ranked_count) from public.ball_knower_leaderboard('week', 50, 'friends')),
  3,
  'ranked_count is the friends cohort size'
);
select is(
  (select array_agg(display_name order by display_name) from public.ball_knower_leaderboard('week', 50, 'friends') where is_me),
  array['FlMe'],
  'the caller''s own row is on the friends board'
);
select is(
  (select array_agg(display_name order by rank, display_name) from public.ball_knower_leaderboard('week')),
  array['FlLonely', 'FlStranger', 'FlFirst', 'FlMe', 'FlSecond'],
  'the default scope is still everyone'
);
select is(
  (select (status, rank, total_points, ranked_count)::text from public.my_ball_knower_standing('week', 'friends')),
  '(ranked,2,30,3)',
  'standing in the friends scope uses the friends cohort'
);
select is(
  (select (status, rank, ranked_count)::text from public.my_ball_knower_standing('week')),
  '(ranked,4,5)',
  'standing in the default scope is unchanged'
);

select tests.act_as((select v from tests.fx where k = 'lonely'));
select is(
  (select (status, rank, ranked_count)::text from public.my_ball_knower_standing('week', 'friends')),
  '(ranked,1,1)',
  'a player with no friends is alone on their friends board'
);

select tests.act_as((select v from tests.fx where k = 'thin'));
select is(
  (select (status, ranked_count)::text from public.my_ball_knower_standing('week', 'friends')),
  '(unranked,1)',
  'the pick floor applies in the friends scope too'
);

select tests.act_as((select v from tests.fx where k = 'me'));
select throws_ok($$ select * from public.ball_knower_leaderboard('week', 50, 'enemies') $$, '22023', 'invalid_scope', 'an unknown scope is rejected');
select throws_ok($$ select * from public.my_ball_knower_standing('week', 'enemies') $$, '22023', 'invalid_scope', 'an unknown scope is rejected for standing');

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok($$ select * from public.ball_knower_leaderboard('week', 50, 'friends') $$, '42501', 'guests_cannot_have_friends', 'a guest has no friends board');
select is(
  (select count(*)::integer from public.ball_knower_leaderboard('week')),
  5,
  'a guest can still read the everyone board'
);

select * from finish();
rollback;
