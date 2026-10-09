-- Tests for prompts.delete_post (0193): admin-only hard delete that works on
-- any status, responses or not, and cascades to everything under the post.

begin;
select plan(9);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('alice', tests.mkuser('alice'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

-- Same helpers as 0095's test: tests.act_as doesn't put an email in its
-- synthetic JWT, and is_admin() matches on auth.jwt()->>'email'.
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

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
  ))
);

-- Alice answers with a comment, so the post has a response and a comment to cascade.
select tests.act_as((select v from tests.fx where k = 'alice'));
select prompts.submit_response(
  (select v from tests.fx where k = 'post'),
  jsonb_build_object(
    (select id::text from public.prompt_slots where post_id = (select v from tests.fx where k = 'post')),
    jsonb_build_array((select id::text from public.prompt_slot_options
      where slot_id = (select id from public.prompt_slots where post_id = (select v from tests.fx where k = 'post')) limit 1))
  ),
  'my take'
);

select throws_ok(
  format($$ select prompts.delete_post(%L) $$, (select v from tests.fx where k = 'post')),
  '42501', 'not_authorized', 'a non-admin cannot delete a post'
);
select ok(
  exists (select 1 from public.prompt_posts where id = (select v from tests.fx where k = 'post')),
  'and the post is still there'
);

select tests.act_as_prompts_admin();
select lives_ok(
  format($$ select prompts.delete_post(%L) $$, (select v from tests.fx where k = 'post')),
  'an admin can delete a post that has responses'
);

select tests.act_as_admin();
select is(
  (select count(*)::int from public.prompt_posts where id = (select v from tests.fx where k = 'post')),
  0, 'the post is gone'
);
select is(
  (select count(*)::int from public.prompt_slots where post_id = (select v from tests.fx where k = 'post')),
  0, 'its slots are gone'
);
select is(
  (select count(*)::int from public.prompt_responses where post_id = (select v from tests.fx where k = 'post')),
  0, 'its responses are gone'
);

select tests.act_as_prompts_admin();
select throws_ok(
  format($$ select prompts.delete_post(%L) $$, (select v from tests.fx where k = 'post')),
  'P0002', 'post_not_found', 'deleting a post that no longer exists is reported'
);

select tests.act_as_admin();
select ok(
  not has_function_privilege('anon', 'prompts.delete_post(uuid)', 'EXECUTE'),
  'anon cannot execute it'
);
select ok(
  has_function_privilege('authenticated', 'prompts.delete_post(uuid)', 'EXECUTE'),
  'authenticated can reach it (is_admin() does the gating)'
);

select * from finish();
rollback;
