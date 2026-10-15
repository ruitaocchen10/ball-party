begin;
select plan(18);

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
insert into public.prompt_slot_options (id, slot_id, label, sublabel, team_code) values
  ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Chiefs', null, 'KC'),
  ('50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Bills', null, 'BUF');
insert into public.prompt_comments (post_id, author_id, body, posted_with_pick) values
  ('10000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'friend'), 'Mahomes in a walk', true),
  ('10000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'friend'), 'Secret take', true);
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned, created_at) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'friend'),   array['50000000-0000-0000-0000-000000000001'::uuid], 25,   now() - interval '3 days'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'friend'),   array['50000000-0000-0000-0000-000000000002'::uuid], null, now() - interval '1 hour'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'stranger'), array[gen_random_uuid()], null, now() - interval '30 minutes'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000003', (select v from tests.fx where k = 'friend'),   array[gen_random_uuid()], 25,   now() - interval '60 days');

-- Multiplayer: the friend beats me in one arcade match, loses another to me, wins a solo-mode run,
-- and wins an arcade match alone (one player).
insert into public.lobbies (id, code, host_id)
values ('60000000-0000-0000-0000-000000000001', 'FAL01', (select v from tests.fx where k = 'me'));
insert into public.runs (id, lobby_id, mode, status, started_at, ended_at) values
  ('30000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'arcade', 'finished', now() - interval '4 hours', now() - interval '3 hours'),
  ('30000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000001', 'arcade', 'finished', now() - interval '4 hours', now() - interval '3 hours'),
  ('30000000-0000-0000-0000-000000000003', null, 'solo', 'finished', now() - interval '4 hours', now() - interval '3 hours'),
  ('30000000-0000-0000-0000-000000000004', '60000000-0000-0000-0000-000000000001', 'arcade', 'finished', now() - interval '4 hours', now() - interval '3 hours');
insert into public.matches (id, run_id, game, seq, status, started_at, ended_at)
select ('40000000-0000-0000-0000-00000000000' || n)::uuid, ('30000000-0000-0000-0000-00000000000' || n)::uuid,
       'higher_or_lower', 1, 'complete', now() - interval '4 hours', now() - interval '3 hours'
  from generate_series(1, 4) n;
insert into public.run_participants (run_id, user_id, seat) values
  ('30000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'friend'), 0),
  ('30000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'me'), 1),
  ('30000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'friend'), 0),
  ('30000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'me'), 1),
  ('30000000-0000-0000-0000-000000000003', (select v from tests.fx where k = 'friend'), 0),
  ('30000000-0000-0000-0000-000000000004', (select v from tests.fx where k = 'friend'), 0);
insert into public.match_players (match_id, run_id, user_id, placement, raw_score) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'friend'), 1, 12),
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'me'), 2, 5),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'friend'), 2, 3),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'me'), 1, 9),
  ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', (select v from tests.fx where k = 'friend'), 1, 8),
  ('40000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000004', (select v from tests.fx where k = 'friend'), 1, 7);

-- Solo bests: the friend raised both 2 hours ago and the stranger raised one; a 40-day-old best is out of the window.
insert into public.higher_or_lower_player_stats (user_id, all_time_high, updated_at) values
  ((select v from tests.fx where k = 'friend'), 14, now() - interval '2 hours'),
  ((select v from tests.fx where k = 'stranger'), 30, now() - interval '2 hours');
insert into public.qb_season_builder_player_stats (user_id, mode, best_score, updated_at) values
  ((select v from tests.fx where k = 'friend'), 'visible', 88.5, now() - interval '20 minutes'),
  ((select v from tests.fx where k = 'friend'), 'hidden', 70.0, now() - interval '40 days');

select tests.act_as((select v from tests.fx where k = 'me'));

select is(
  (select array_agg(event_type order by occurred_at desc) from public.friend_activity()),
  array['high_score', 'high_score', 'win'],
  'the feed has the friend''s bests and multiplayer win, newest first, and no prompt answers'
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
  (select count(*)::integer from public.friend_activity() where event_type = 'win'),
  1,
  'only the multiplayer win appears: not the loss, the solo run or the one-player match'
);
select is(
  (select (game, placement, raw_score, run_mode)::text from public.friend_activity() where event_type = 'win'),
  '(higher_or_lower,1,12,arcade)',
  'a win carries game, placement, score and run mode'
);
select is(
  (select (opponents, opponent_you, opponent_count)::text from public.friend_activity() where event_type = 'win'),
  '(,t,1)',
  'a win says the caller was the opponent; only friends are named'
);
select is(
  (select array_agg(game || ':' || friend_rank || '/' || friend_count order by game) from public.friend_activity() where event_type = 'high_score'),
  array['higher_or_lower:1/1', 'qb_season_builder:1/1'],
  'a high score is ranked among the caller and their friends'
);
select is(
  (select array_agg(game || ':' || raw_score || ':' || coalesce(mode, '') order by game) from public.friend_activity() where event_type = 'high_score'),
  array['higher_or_lower:14:', 'qb_season_builder:88.5:visible'],
  'a high score carries the game, the new best and the QB mode; a best older than 30 days is left out'
);
select is(
  (select count(*)::integer
     from pg_proc p, unnest(p.proargnames) n
    where p.proname = 'friend_activity' and n in ('chosen_option_ids', 'is_guest', 'is_private', 'deleted_at')),
  0,
  'the feed never returns raw option ids or private profile columns'
);

select is((select count(*)::integer from public.friend_activity(1)), 1, 'p_limit caps the rows');
select is(
  (select event_type from public.friend_activity(10, (select occurred_at from public.friend_activity() offset 1 limit 1)) limit 1),
  'win',
  'p_before pages past the rows already seen'
);

-- Which friends answered a prompt: the fact only, whether or not it has locked.
select is(
  (select array_agg(post_id::text || ':' || display_name order by post_id) from public.friends_who_answered(array[
    '10000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000002'::uuid, '10000000-0000-0000-0000-000000000003'::uuid])),
  array['10000000-0000-0000-0000-000000000001:FaFriend', '10000000-0000-0000-0000-000000000002:FaFriend', '10000000-0000-0000-0000-000000000003:FaFriend'],
  'friends_who_answered names a friend who answered, on an open or a locked prompt'
);
select is(
  (select count(*)::integer from public.friends_who_answered(array['10000000-0000-0000-0000-000000000002'::uuid]) where actor_id = (select v from tests.fx where k = 'stranger')),
  0,
  'a stranger who answered is not named'
);
select is(
  (select count(*)::integer
     from pg_proc p, unnest(p.proargnames) n
    where p.proname = 'friends_who_answered' and n in ('chosen_option_ids', 'response', 'take_body')),
  0,
  'and the pick itself never comes down'
);

-- A void prompt drops out entirely.
select tests.act_as_admin();
update public.prompt_posts set status = 'void', void_reason = 'test' where id = '10000000-0000-0000-0000-000000000002';
select tests.act_as((select v from tests.fx where k = 'me'));
select is((select count(*)::integer from public.friends_who_answered(array['10000000-0000-0000-0000-000000000002'::uuid])), 1, 'friends_who_answered does not hide a void prompt: the card is the feed''s call');

-- Removing the friend empties the feed.
select public.remove_friend((select v from tests.fx where k = 'friend'));
select is((select count(*)::integer from public.friend_activity()), 0, 'unfriending removes their activity');

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is((select count(*)::integer from public.friend_activity()), 0, 'a player with no friends has an empty feed');

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok($$ select * from public.friend_activity() $$, '42501', 'guests_cannot_have_friends', 'a guest has no feed');

select * from finish();
rollback;
