begin;
select plan(4);

\ir support/harness.psql

-- Aggregate cohort checks: keep local seed responses out of the fixture. The
-- enclosing transaction rolls this back.
delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('leader',  tests.mkuser('Leader')),
  ('viewer',  tests.mkuser('Viewer')),
  ('deleted', tests.mkuser('Deleted'));

insert into public.prompt_posts (
  id, template_kind, template_name, author_id, caption, prompt_text,
  resolution_criteria, lock_at, status, resolved_at
) values
  ('10000000-0000-0000-0000-000000000001', 'game_pick', 'Test', (select v from tests.fx where k = 'leader'), 'T', 'T', 'T', now() - interval '2 days', 'resolved', now() - interval '1 day');

insert into public.prompt_slots (id, post_id, label, shape, points) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Pick', 'pick', 30);

insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'leader'),  array[gen_random_uuid()], 20),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'viewer'),  array[gen_random_uuid()], 10),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'deleted'), array[gen_random_uuid()], 30);

select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'rankings_visible'),
  0,
  'the rankings_visible opt-out column is gone'
);

-- Deleting the account (via the real RPC) is what removes it from the cohort.
select tests.act_as((select v from tests.fx where k = 'deleted'));
select public.delete_own_account();

select tests.act_as((select v from tests.fx where k = 'leader'));
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  100,
  'a deleted player does not shrink the cohort another player ranks against'
);

select tests.act_as((select v from tests.fx where k = 'viewer'));
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  50,
  'a deleted player is excluded from the cohort entirely, not just from first place'
);

select tests.act_as((select v from tests.fx where k = 'deleted'));
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  null,
  'a deleted player has no percentile'
);

select * from finish();
rollback;
