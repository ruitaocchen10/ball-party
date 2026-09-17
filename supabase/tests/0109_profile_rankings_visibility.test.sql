begin;
select plan(4);

\ir support/harness.psql

-- This suite checks an aggregate cohort, so keep local seed responses out of
-- its deterministic fixture. The enclosing transaction always rolls this
-- back after the assertions.
delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('leader', tests.mkuser('Leader')),
  ('viewer', tests.mkuser('Viewer')),
  ('hidden', tests.mkuser('Hidden'));

update public.profiles set rankings_visible = false where id = (select v from tests.fx where k = 'hidden');

insert into public.prompt_posts (
  id, template_kind, template_name, author_id, caption, prompt_text,
  resolution_criteria, lock_at, status, resolved_at
) values
  ('10000000-0000-0000-0000-000000000001', 'game_pick', 'Test', (select v from tests.fx where k = 'leader'), 'Test', 'Test', 'Test', now() - interval '2 days', 'resolved', now() - interval '1 day');

insert into public.prompt_slots (id, post_id, label, shape, points) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Pick', 'pick', 30);

-- Hidden outscores everyone. If they still counted in the cohort, leader
-- would rank 2nd of 3 instead of 1st of 2.
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'leader'), array[gen_random_uuid()], 20),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'viewer'), array[gen_random_uuid()], 10),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (select v from tests.fx where k = 'hidden'), array[gen_random_uuid()], 30);

select tests.act_as((select v from tests.fx where k = 'leader'));
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  100,
  'a hidden player does not shrink the visible cohort another player ranks against'
);

select tests.act_as((select v from tests.fx where k = 'viewer'));
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  50,
  'the visible cohort excludes hidden players entirely, not just from first place'
);

select tests.act_as((select v from tests.fx where k = 'hidden'));
select is(
  (select total_points from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  30,
  'hiding yourself does not blank your own point total'
);
select is(
  (select percentile from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  null,
  'hiding yourself blanks your own percentile, the same as having no resolved picks'
);

select * from finish();
rollback;
