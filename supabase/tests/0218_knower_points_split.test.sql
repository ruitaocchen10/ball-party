-- Tests for 0218: the profile highlights split points into picks and likes.

begin;
select plan(5);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values
  ('admin', tests.mkuser('admin')),
  ('alice', tests.mkuser('alice')),
  ('bob',   tests.mkuser('bob')),
  ('cy',    tests.mkuser('cy'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

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

create function tests.who(p_k text) returns uuid
language sql stable as $$ select v from tests.fx where k = p_k $$;

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day', '[]'::jsonb
);

select tests.act_as(tests.who('alice'));
select prompts.submit_response(tests.who('post'), '{}'::jsonb, 'Chalk all day');

select tests.act_as_admin();
insert into tests.fx (k, v)
select 'alice_take', id from public.prompt_comments
 where post_id = tests.who('post') and author_id = tests.who('alice') and parent_comment_id is null;

select tests.act_as(tests.who('bob'));
select public.react_to_take(tests.who('alice_take'), 1::smallint);
select tests.act_as(tests.who('cy'));
select public.react_to_take(tests.who('alice_take'), 1::smallint);

-- Alice has no scored picks, only two likes.
select tests.act_as(tests.who('alice'));
select is(
  (select pick_points from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  0, 'no scored picks gives zero pick points');
select is(
  (select like_points from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  2, 'two likes give two like points');
select is(
  (select total_points from public.my_profile_knower_highlights() where window_key = 'lifetime'),
  2, 'and the total is still the sum');

-- A like given 40 days ago leaves the week window but stays in the year.
select tests.act_as_admin();
update public.take_reactions set updated_at = now() - interval '40 days'
 where comment_id = tests.who('alice_take') and reactor_id = tests.who('cy');
select tests.act_as(tests.who('alice'));
select is(
  (select like_points from public.my_profile_knower_highlights() where window_key = 'week'),
  1, 'the split follows the window');

select tests.act_as(tests.who('bob'));
select is(
  (select like_points from public.get_profile_knower_highlights(tests.who('bob')) where window_key = 'lifetime'),
  0, 'the same split is readable for a profile the viewer may open');

select * from finish();
rollback;
