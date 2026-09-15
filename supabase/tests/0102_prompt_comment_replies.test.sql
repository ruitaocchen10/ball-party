-- Tests for 0102: threaded replies on prompt_comments.

begin;
select plan(8);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('alice', tests.mkuser('alice'));
insert into tests.fx (k, v) values ('bob',   tests.mkuser('bob'));

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

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day', '[]'::jsonb
);
insert into tests.fx (k, v)
select 'other_post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day', '[]'::jsonb
);

-- ------------------------------------------------------------------ a take --

select tests.act_as((select v from tests.fx where k = 'alice'));
insert into tests.fx (k, v)
select 'alice_take', prompts.post_comment((select v from tests.fx where k = 'post'), 'Book it, home team wins');

select is((select parent_comment_id from public.prompt_comments where id = (select v from tests.fx where k = 'alice_take')),
  null, 'a plain take has no parent');

-- ------------------------------------------------------------------- replies --

select tests.act_as((select v from tests.fx where k = 'bob'));
insert into tests.fx (k, v)
select 'bob_reply', prompts.post_comment(
  (select v from tests.fx where k = 'post'), 'No shot', (select v from tests.fx where k = 'alice_take')
);

select is((select parent_comment_id from public.prompt_comments where id = (select v from tests.fx where k = 'bob_reply')),
  (select v from tests.fx where k = 'alice_take'), 'a reply records which take it answers');
select is((select posted_with_pick from public.prompt_comments where id = (select v from tests.fx where k = 'bob_reply')),
  false, 'a reply is never flagged as posted with a pick');

select throws_ok(
  format(
    $$ select prompts.post_comment(%L, 'wrong post', %L) $$,
    (select v from tests.fx where k = 'other_post'), (select v from tests.fx where k = 'alice_take')
  ),
  'P0002', 'parent_not_found', 'a parent from a different post is rejected'
);

select throws_ok(
  format($$ select prompts.post_comment(%L, 'ghost parent', %L) $$, (select v from tests.fx where k = 'post'), gen_random_uuid()),
  'P0002', 'parent_not_found', 'a parent id that does not exist is rejected'
);

select throws_ok(
  format(
    $$ select prompts.post_comment(%L, 'reply to a reply', %L) $$,
    (select v from tests.fx where k = 'post'), (select v from tests.fx where k = 'bob_reply')
  ),
  '22023', 'nested_reply', 'replying to a reply is rejected — threads stay one level deep'
);

select throws_ok(
  $$ select prompts.post_comment(gen_random_uuid(), 'no such post') $$,
  'P0002', 'post_not_found', 'post_comment still checks the post itself exists'
);

select is((select count(*)::int from public.prompt_comments where post_id = (select v from tests.fx where k = 'post')),
  2, 'only the take and its one valid reply were actually written — every rejected call left no row behind');

select * from finish();
rollback;
