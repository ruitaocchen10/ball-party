-- Tests for 0208: answering always leaves a take, empty when nothing was written.

begin;
select plan(7);
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

-- ------------------------------------------------- answering with no words --

select tests.act_as((select v from tests.fx where k = 'alice'));
select prompts.submit_response((select v from tests.fx where k = 'post'), '{}'::jsonb);

select is(
  (select count(*)::int from public.prompt_comments
    where post_id = (select v from tests.fx where k = 'post')
      and author_id = (select v from tests.fx where k = 'alice')
      and posted_with_pick and parent_comment_id is null and body = ''),
  1, 'an answer with no comment still leaves one empty take');

-- -------------------------------------------------- resubmitting with words --

select prompts.submit_response((select v from tests.fx where k = 'post'), '{}'::jsonb, '  Chalk all day  ');

select is(
  (select body from public.prompt_comments
    where post_id = (select v from tests.fx where k = 'post')
      and author_id = (select v from tests.fx where k = 'alice') and parent_comment_id is null),
  'Chalk all day', 'a resubmit with a comment fills the empty take in, trimmed');

select is(
  (select count(*)::int from public.prompt_comments
    where post_id = (select v from tests.fx where k = 'post')
      and author_id = (select v from tests.fx where k = 'alice') and parent_comment_id is null),
  1, 'and does not add a second take');

-- ------------------------------------------------------ answering with words --

select tests.act_as((select v from tests.fx where k = 'bob'));
select prompts.submit_response((select v from tests.fx where k = 'post'), '{}'::jsonb, 'Underdog');

select is(
  (select body from public.prompt_comments
    where post_id = (select v from tests.fx where k = 'post')
      and author_id = (select v from tests.fx where k = 'bob')),
  'Underdog', 'an answer with a comment keeps it as the take''s body');

-- ------------------------------------------------- empty bodies stay narrow --

select throws_ok(
  format($$ select prompts.post_comment(%L, '   ') $$, (select v from tests.fx where k = 'post')),
  '23514', null, 'a take posted without picks still needs words');

select throws_ok(
  format($$ select prompts.post_comment(%L, '   ', %L) $$,
    (select v from tests.fx where k = 'post'),
    (select id from public.prompt_comments where author_id = (select v from tests.fx where k = 'alice') and parent_comment_id is null)),
  '23514', null, 'a reply to an empty take still needs words');

-- A reply to an empty take is an ordinary reply, and notifies its owner.
insert into tests.fx (k, v)
select 'reply', prompts.post_comment(
  (select v from tests.fx where k = 'post'), 'Respect',
  (select id from public.prompt_comments where author_id = (select v from tests.fx where k = 'alice') and parent_comment_id is null));

select tests.act_as((select v from tests.fx where k = 'alice'));
select is(
  (select count(*)::int from public.notifications
    where recipient_id = (select v from tests.fx where k = 'alice') and type = 'take_reply'),
  1, 'a reply to a take notifies its owner whether or not the take has words');

select * from finish();
rollback;
