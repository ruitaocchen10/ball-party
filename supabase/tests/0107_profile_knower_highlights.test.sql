begin;
select plan(4);

\ir support/harness.psql

-- This suite checks an aggregate cohort, so keep local seed responses out of
-- its deterministic fixture. The enclosing transaction always rolls this
-- back after the assertions.
delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('leader', tests.mkuser('Leader')),
  ('viewer', tests.mkuser('Viewer'));

insert into public.prompt_posts (
  id, template_kind, template_name, author_id, caption, prompt_text,
  resolution_criteria, lock_at, status, resolved_at
) values
  ('10000000-0000-0000-0000-000000000001', 'game_pick', 'Test', (select v from tests.fx where k = 'leader'), 'Test', 'Test', 'Test', now() - interval '2 days', 'resolved', now() - interval '1 day'),
  ('10000000-0000-0000-0000-000000000002', 'game_pick', 'Old test', (select v from tests.fx where k = 'leader'), 'Test', 'Test', 'Test', now() - interval '400 days', 'resolved', now() - interval '366 days');

insert into public.prompt_slots (id, post_id, label, shape, points) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Pick', 'pick', 10),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Old pick', 'pick', 10);

insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'leader'), array[gen_random_uuid()], 20),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'viewer'), array[gen_random_uuid()], 10),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', (select v from tests.fx where k = 'viewer'), array[gen_random_uuid()], 30);

select tests.act_as((select v from tests.fx where k = 'viewer'));

select is(
  (select total_points from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  40,
  'lifetime totals include all resolved prompt points'
);
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  100,
  'lifetime percentile places the caller in the active ball knower cohort'
);
select is(
  (select total_points from public.my_profile_knower_highlights() where window_key = 'week'),
  10,
  'week totals use the post resolution date, not response creation'
);
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'week'),
  50,
  'week percentile uses the same reporting window as the total'
);

select * from finish();
rollback;
