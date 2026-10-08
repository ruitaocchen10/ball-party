begin;
select plan(6);

\ir support/harness.psql

delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('me',    tests.mkuser('LuMe')),
  ('ok',    tests.mkuser('LuOk')),
  ('theyb', tests.mkuser('LuTheyBlock')),
  ('iblk',  tests.mkuser('LuIBlock'));

insert into public.prompt_posts (id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, status, resolved_at)
values ('10000000-0000-0000-0000-000000000001', 'game_pick', 'T', (select v from tests.fx where k = 'me'), 'T', 'T', 'T', now() - interval '2 days', 'resolved', now() - interval '1 day');
insert into public.prompt_slots (id, post_id, label, shape, points) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'A', 'pick', 10),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'B', 'pick', 10),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'C', 'pick', 10);

insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
select s.post_id, s.id, u.v, array[gen_random_uuid()], 10
  from public.prompt_slots s cross join tests.fx u;

-- theyb blocks me; I block iblk.
select tests.act_as((select v from tests.fx where k = 'theyb'));
select public.block_user((select v from tests.fx where k = 'me'));
select tests.act_as((select v from tests.fx where k = 'me'));
select public.block_user((select v from tests.fx where k = 'iblk'));

select is(
  (select username from public.ball_knower_leaderboard('week') where profile_id = (select v from tests.fx where k = 'ok')),
  'LuOk',
  'a row carries the player''s username'
);
select ok(
  (select username is not null from public.ball_knower_leaderboard('week') where is_me),
  'the caller''s own row carries a username'
);
select is(
  (select username from public.ball_knower_leaderboard('week') where profile_id = (select v from tests.fx where k = 'theyb')),
  null,
  'no username for a player who blocked the caller'
);
select is(
  (select username from public.ball_knower_leaderboard('week') where profile_id = (select v from tests.fx where k = 'iblk')),
  null,
  'no username for a player the caller blocked'
);
select is(
  (select count(*)::int from public.ball_knower_leaderboard('week')),
  4,
  'blocked players still rank (only the link is withheld)'
);

select tests.act_as_admin();
select ok(
  has_function_privilege('authenticated', 'public.ball_knower_leaderboard(text,integer,text)', 'execute')
    and not has_function_privilege('anon', 'public.ball_knower_leaderboard(text,integer,text)', 'execute'),
  'only signed-in players can call the leaderboard'
);

select * from finish();
rollback;
