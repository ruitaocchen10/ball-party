begin;
select plan(14);

\ir support/harness.psql

delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('me',       tests.mkuser('FaMe')),
  ('friend',   tests.mkuser('FaFriend')),
  ('stranger', tests.mkuser('FaStranger')),
  ('guest',    tests.mkguest('FaGuest'));

select tests.act_as((select v from tests.fx where k = 'friend'));
select public.send_friend_request('FaMe');
select tests.act_as((select v from tests.fx where k = 'me'));
select public.accept_friend_request((select v from tests.fx where k = 'friend'));

select tests.act_as_admin();

-- Two prompts: one resolved (friend scored 25), one still open. The stranger
-- answers the open one too.
insert into public.prompt_posts (id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, status, resolved_at) values
  ('10000000-0000-0000-0000-000000000001', 'game_pick', 'T', (select v from tests.fx where k = 'me'), 'Resolved one', 'T', 'T', now() - interval '2 days', 'resolved', now() - interval '1 day'),
  ('10000000-0000-0000-0000-000000000002', 'game_pick', 'T', (select v from tests.fx where k = 'me'), 'Open one',     'T', 'T', now() + interval '2 days', 'open', null),
  ('10000000-0000-0000-0000-000000000003', 'game_pick', 'T', (select v from tests.fx where k = 'me'), 'Old one',      'T', 'T', now() - interval '60 days', 'resolved', now() - interval '59 days');
insert into public.prompt_slots (id, post_id, label, shape, points) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'A', 'pick', 25),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'B', 'pick', 25),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', 'C', 'pick', 25);
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned, created_at) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'friend'),   array[gen_random_uuid()], 25,   now() - interval '3 days'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'friend'),   array[gen_random_uuid()], null, now() - interval '1 hour'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'stranger'), array[gen_random_uuid()], null, now() - interval '30 minutes'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000003', (select v from tests.fx where k = 'friend'),   array[gen_random_uuid()], 25,   now() - interval '60 days');

-- A finished solo match for the friend and one for the stranger.
insert into public.runs (id, mode, status, started_at, ended_at) values
  ('30000000-0000-0000-0000-000000000001', 'solo', 'finished', now() - interval '2 hours', now() - interval '90 minutes'),
  ('30000000-0000-0000-0000-000000000002', 'solo', 'finished', now() - interval '2 hours', now() - interval '90 minutes');
insert into public.run_participants (run_id, user_id, seat) values
  ('30000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'friend'), 0),
  ('30000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'stranger'), 0);
insert into public.matches (id, run_id, game, seq, status, started_at, ended_at) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'higher_or_lower', 1, 'complete', now() - interval '2 hours', now() - interval '90 minutes'),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'higher_or_lower', 1, 'complete', now() - interval '2 hours', now() - interval '90 minutes');
insert into public.match_players (match_id, run_id, user_id, placement, raw_score) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'friend'), 1, 12),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'stranger'), 1, 99);

select tests.act_as((select v from tests.fx where k = 'me'));

select is(
  (select array_agg(event_type order by occurred_at desc) from public.friend_activity()),
  array['pick_made', 'match_result', 'pick_result', 'pick_made'],
  'the feed has the friend''s picks, match and result, newest first'
);
select is(
  (select count(*)::integer from public.friend_activity() where actor_id = (select v from tests.fx where k = 'stranger')),
  0,
  'a stranger''s activity is not in the feed'
);
select is(
  (select count(*)::integer from public.friend_activity() where actor_id = (select v from tests.fx where k = 'me')),
  0,
  'your own activity is not in your friends feed'
);
select is(
  (select (post_caption, points)::text from public.friend_activity() where event_type = 'pick_result'),
  '("Resolved one",25)',
  'a result carries the prompt and the points earned'
);
select is(
  (select post_caption from public.friend_activity() where event_type = 'pick_made' order by occurred_at desc limit 1),
  'Open one',
  'a pick event names the prompt'
);
select is(
  (select (game, placement, raw_score, run_mode)::text from public.friend_activity() where event_type = 'match_result'),
  '(higher_or_lower,1,12,solo)',
  'a match event carries game, placement, score and run mode'
);
select is(
  (select count(*)::integer from public.friend_activity() where post_caption = 'Old one'),
  0,
  'events older than 30 days are not included'
);
select is(
  (select count(*)::integer from public.friend_activity() where event_type = 'pick_made' and post_caption = 'Old one'),
  0,
  'picks older than 30 days are not included'
);
select is(
  (select count(*)::integer
     from pg_proc p, unnest(p.proargnames) n
    where p.proname = 'friend_activity' and n in ('chosen_option_ids', 'is_guest', 'is_private', 'deleted_at')),
  0,
  'the feed never returns the chosen options or private profile columns'
);

select is((select count(*)::integer from public.friend_activity(1)), 1, 'p_limit caps the rows');
select is(
  (select event_type from public.friend_activity(10, (select occurred_at from public.friend_activity() offset 1 limit 1)) limit 1),
  'pick_result',
  'p_before pages past the rows already seen'
);

-- Removing the friend empties the feed.
select public.remove_friend((select v from tests.fx where k = 'friend'));
select is((select count(*)::integer from public.friend_activity()), 0, 'unfriending removes their activity');

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is((select count(*)::integer from public.friend_activity()), 0, 'a player with no friends has an empty feed');

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok($$ select * from public.friend_activity() $$, '42501', 'guests_cannot_have_friends', 'a guest has no feed');

select * from finish();
rollback;
