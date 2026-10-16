-- Tests for 0216: balls on takes feed the Ball Knower score.

begin;
select plan(21);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values
  ('admin', tests.mkuser('admin')),
  ('alice', tests.mkuser('alice')),
  ('bob',   tests.mkuser('bob')),
  ('cy',    tests.mkuser('cy')),
  ('guest', tests.mkguest('guest'));

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

-- Alice answers with words, Bob answers with picks only. Both leave a take.
select tests.act_as(tests.who('alice'));
select prompts.submit_response(tests.who('post'), '{}'::jsonb, 'Chalk all day');
select tests.act_as(tests.who('bob'));
select prompts.submit_response(tests.who('post'), '{}'::jsonb);

select tests.act_as_admin();
insert into tests.fx (k, v)
select 'alice_take', id from public.prompt_comments
 where post_id = tests.who('post') and author_id = tests.who('alice') and parent_comment_id is null;
insert into tests.fx (k, v)
select 'bob_take', id from public.prompt_comments
 where post_id = tests.who('post') and author_id = tests.who('bob') and parent_comment_id is null;

select tests.act_as(tests.who('bob'));
insert into tests.fx (k, v) select 'reply', prompts.post_comment(tests.who('post'), 'a reply', tests.who('alice_take'));

-- ------------------------------------------------------------ who may react --

select tests.act_as(tests.who('cy'));
select is((select net_balls from public.react_to_take(tests.who('alice_take'), 1::smallint)), 1,
  'anyone with an account can like a take');
select throws_ok(
  format('select public.react_to_take(%L, -1::smallint)', tests.who('alice_take')),
  '42501', 'dislike_friends_only', 'a stranger cannot dislike');

select tests.act_as(tests.who('alice'));
select throws_ok(
  format('select public.react_to_take(%L, 1::smallint)', tests.who('alice_take')),
  '42501', 'cannot_react_to_own_take', 'you cannot react to your own take');
select throws_ok(
  format('select public.react_to_take(%L, 1::smallint)', tests.who('reply')),
  'P0002', 'take_not_found', 'a reply is not reactable');
select throws_ok(
  format('select public.react_to_take(%L, 2::smallint)', tests.who('bob_take')),
  '22023', 'invalid_reaction', 'only 1, -1 and 0 are reactions');

select tests.act_as(tests.who('guest'));
select throws_ok(
  format('select public.react_to_take(%L, 1::smallint)', tests.who('alice_take')),
  '42501', 'guests_cannot_react', 'a guest cannot react');

select tests.act_as_admin();
select throws_ok(
  format('select public.react_to_take(%L, 1::smallint)', tests.who('alice_take')),
  '28000', 'not_authenticated', 'signed out cannot react');

-- ---------------------------------------------------------------- friends --

select tests.act_as(tests.who('bob'));
select public.send_friend_request('alice');
select tests.act_as(tests.who('alice'));
select public.accept_friend_request(tests.who('bob'));

select tests.act_as(tests.who('bob'));
select is((select net_balls from public.react_to_take(tests.who('alice_take'), -1::smallint)), 0,
  'a friend can dislike: the like and dislike cancel to 0');
select is((select my_reaction from public.react_to_take(tests.who('alice_take'), -1::smallint)), (-1)::smallint,
  'asking for the same reaction twice keeps it');
select is((select net_balls from public.react_to_take(tests.who('alice_take'), 1::smallint)), 2,
  'switching a dislike to a like moves the net by two');
select is((select net_balls from public.react_to_take(tests.who('alice_take'), 0::smallint)), 1,
  'zero removes my reaction');

select tests.act_as_admin();
select is((select count(*)::int from public.take_reactions where comment_id = tests.who('alice_take') and reactor_id = tests.who('bob')), 0,
  'and leaves no row behind');

select tests.act_as(tests.who('alice'));
select is((select net_balls from public.react_to_take(tests.who('bob_take'), 1::smallint)), 1,
  'a picks-only take can be reacted to');

-- ---------------------------------------------------------------- summary --

select tests.act_as(tests.who('bob'));
select public.react_to_take(tests.who('alice_take'), -1::smallint);
select is(
  (select (net_balls, my_reaction, can_like, can_dislike)::text from public.take_reaction_summary(array[tests.who('alice_take')])),
  '(0,-1,t,t)', 'the summary gives the net, my reaction and what I can do');

select tests.act_as(tests.who('cy'));
select is(
  (select (net_balls, my_reaction, can_like, can_dislike)::text from public.take_reaction_summary(array[tests.who('alice_take')])),
  '(0,1,t,f)', 'a non-friend can like but not dislike');

select tests.act_as(tests.who('alice'));
select is(
  (select (can_like, can_dislike)::text from public.take_reaction_summary(array[tests.who('alice_take')])),
  '(f,f)', 'your own take offers neither');

select tests.act_as_admin();
select set_config('role', 'anon', true);
select is(
  (select (net_balls, my_reaction, can_like, can_dislike)::text from public.take_reaction_summary(array[tests.who('alice_take')])),
  '(0,0,f,f)', 'a signed-out reader sees the count and no controls');
select set_config('role', 'postgres', true);

-- ------------------------------------------------------------------ score --

-- Alice: cy's like (+1) and bob's dislike (-1) on her take = 0. Give her one more.
select tests.act_as(tests.who('bob'));
select public.react_to_take(tests.who('alice_take'), 1::smallint);
select tests.act_as_admin();

select is(
  (select total_points from private.ball_knower_totals('lifetime') where profile_id = tests.who('alice')),
  2, 'net balls count as points: cy +1 and bob +1');

update public.take_reactions set updated_at = now() - interval '40 days'
 where comment_id = tests.who('alice_take') and reactor_id = tests.who('cy');
select is(
  (select total_points from private.ball_knower_totals('week') where profile_id = tests.who('alice')),
  1, 'a ball given 40 days ago is outside the week');
select is(
  (select total_points from private.ball_knower_totals('year') where profile_id = tests.who('alice')),
  2, 'but inside the year');

select tests.act_as(tests.who('alice'));
select is(
  (select status from public.my_ball_knower_standing('lifetime')),
  'unranked', 'balls alone do not clear the 3-pick floor');
