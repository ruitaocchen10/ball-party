begin;
select plan(23);

\ir support/harness.psql

insert into tests.fx (k, v) values
  ('pub',     tests.mkuser('GpPublic')),
  ('priv',    tests.mkuser('GpPrivate')),
  ('friend',  tests.mkuser('GpFriend')),
  ('stranger', tests.mkuser('GpStranger')),
  ('blocker', tests.mkuser('GpBlocker')),
  ('guest',   tests.mkguest('GpGuest'));

-- priv is private; friend is priv's friend; blocker blocked stranger.
select tests.act_as((select v from tests.fx where k = 'priv'));
select public.set_profile_private(true);
select public.send_friend_request('GpFriend');
select tests.act_as((select v from tests.fx where k = 'friend'));
select public.accept_friend_request((select v from tests.fx where k = 'priv'));
select tests.act_as((select v from tests.fx where k = 'blocker'));
select public.block_user((select v from tests.fx where k = 'stranger'));

-- Give 'priv' a scored pick so the body has something to return.
select tests.act_as_admin();
delete from public.prompt_posts;
insert into public.prompt_posts (id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, status, resolved_at)
values ('10000000-0000-0000-0000-000000000001', 'game_pick', 'T', (select v from tests.fx where k = 'pub'), 'T', 'T', 'T', now() - interval '2 days', 'resolved', now() - interval '1 day');
insert into public.prompt_slots (id, post_id, label, shape, points)
values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Pick', 'pick', 30);
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'priv'), array[gen_random_uuid()], 30);

-- ---------------------------------------------------------------- public ---

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is(
  (select (username, relationship, can_view, is_private)::text from public.get_profile('gppublic')),
  '(GpPublic,none,t,f)',
  'a public profile is readable by any account'
);
select is(
  (select (username, relationship, can_view, is_private)::text from public.get_profile('GpPrivate')),
  '(GpPrivate,none,f,t)',
  'a private profile shows its header but not its body to a stranger'
);
select is(
  (select count(*)::integer from public.get_profile_knower_highlights((select v from tests.fx where k = 'priv'))),
  0,
  'a stranger gets no highlights for a private profile'
);
select is(
  (select count(*)::integer from public.get_profile_match_history((select v from tests.fx where k = 'priv'))),
  0,
  'a stranger gets no match history for a private profile'
);
select is(
  (select count(*)::integer from public.get_profile_knower_highlights((select v from tests.fx where k = 'pub'))),
  4,
  'a stranger gets the four highlight windows for a public profile'
);
select is((select count(*)::integer from public.get_profile('nobody_gp')), 0, 'an unknown username returns nothing');
select is((select count(*)::integer from public.get_profile('x')), 0, 'a malformed username returns nothing');
select is((select count(*)::integer from public.get_profile(null)), 0, 'null returns nothing');
select is((select count(*)::integer from public.get_profile('GpGuest')), 0, 'a guest has no profile to read');

-- --------------------------------------------------------------- friends ---

select tests.act_as((select v from tests.fx where k = 'friend'));
select is(
  (select (relationship, can_view)::text from public.get_profile('GpPrivate')),
  '(friends,t)',
  'a friend can open a private profile'
);
select is(
  (select total_points from public.get_profile_knower_highlights((select v from tests.fx where k = 'priv')) where window_key = 'lifetime'),
  30,
  'a friend sees a private player''s knower highlights'
);

-- ------------------------------------------------------------------ self ---

select tests.act_as((select v from tests.fx where k = 'priv'));
select is(
  (select (relationship, can_view)::text from public.get_profile('GpPrivate')),
  '(self,t)',
  'you can always open your own private profile'
);
select is(
  (select total_points from public.get_profile_knower_highlights((select v from tests.fx where k = 'priv')) where window_key = 'lifetime'),
  30,
  'the my_ and get_ highlight paths agree for yourself'
);
select is(
  (select total_points from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  30,
  'my_profile_knower_highlights still works'
);

-- ----------------------------------------------------------------- block ---

select tests.act_as((select v from tests.fx where k = 'blocker'));
select is(
  (select relationship from public.get_profile('GpStranger')),
  'blocked',
  'the blocker still sees who they blocked'
);
select tests.act_as((select v from tests.fx where k = 'stranger'));
select is((select count(*)::integer from public.get_profile('GpBlocker')), 0, 'someone who blocked you is not found');
select is(
  (select count(*)::integer from public.get_profile_knower_highlights((select v from tests.fx where k = 'blocker'))),
  0,
  'and their body is closed to you even by id'
);

-- ---------------------------------------------------------------- guests ---

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select is((select count(*)::integer from public.get_profile('GpPublic')), 0, 'a guest gets nothing from get_profile');
select is(
  (select count(*)::integer from public.get_profile_knower_highlights((select v from tests.fx where k = 'pub'))),
  0,
  'a guest gets no profile body'
);

-- ------------------------------------------------------- columns exposed ---

select tests.act_as((select v from tests.fx where k = 'stranger'));
select is(
  (select count(*)::integer from pg_proc p where p.proname = 'get_profile' and p.proargnames @> array['is_guest']),
  0,
  'get_profile never returns is_guest'
);
select is(
  (select count(*)::integer from pg_proc p where p.proname = 'get_profile' and p.proargnames @> array['deleted_at']),
  0,
  'get_profile never returns deleted_at'
);

-- ----------------------------------------------------------- rate limiting ---

select tests.act_as((select v from tests.fx where k = 'pub'));
select lives_ok(
  $$ select public.get_profile('GpPrivate') from generate_series(1, 120) $$,
  'a hundred and twenty profile lookups a minute are allowed'
);
select throws_ok(
  $$ select public.get_profile('GpPrivate') $$,
  '54000', 'rate_limited',
  'the next lookup in the minute is refused'
);

select * from finish();
rollback;
