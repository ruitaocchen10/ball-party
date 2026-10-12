-- Tests for APNs sending (0206): what is queued, coalescing, suppression at
-- claim time, the sender's claim/finish contract, and that a broken outbox can
-- never fail the action behind it.

begin;
select plan(37);
\ir support/harness.psql

insert into tests.fx (k, v) values
  ('admin', tests.mkuser('PoAdmin')),
  ('alice', tests.mkuser('PoAlice')),
  ('bob',   tests.mkuser('PoBob')),
  ('cara',  tests.mkuser('PoCara')),
  ('dave',  tests.mkuser('PoDave'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$ select email from auth.users where id = p_id; $$;

create function tests.act_as_prompts_admin() returns void
language plpgsql as $$
declare v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(v_id))::text,
    true);
  perform set_config('role', 'authenticated', true);
end $$;

create function tests.who(p_k text) returns uuid language sql stable as $$ select v from tests.fx where k = p_k $$;

-- Everyone but dave has a device. Alice has two.
select tests.act_as(tests.who('alice'));
select public.register_device_token(repeat('a', 64), 'sandbox');
select public.register_device_token(repeat('e', 64), 'production');
select tests.act_as(tests.who('bob'));
select public.register_device_token(repeat('b', 64), 'sandbox');
select tests.act_as(tests.who('cara'));
select public.register_device_token(repeat('c', 64), 'sandbox');
select tests.act_as(tests.who('admin'));
select public.register_device_token(repeat('f', 64), 'sandbox');

-- ------------------------------------------------------- friend requests ---

select tests.act_as(tests.who('bob'));
select public.send_friend_request('PoAlice');
select public.send_friend_request('PoDave');
select tests.act_as_admin();
select is((select count(*)::integer from public.push_outbox where recipient_id = tests.who('alice') and kind = 'friend_request'), 1,
  'a friend request queues a push for the addressee');
select ok((select item_key like 'n:%' and available_at <= now() from public.push_outbox where recipient_id = tests.who('alice')),
  'for the inbox item, due straight away');
select is((select count(*)::integer from public.push_outbox where recipient_id = tests.who('dave')), 0,
  'nothing is queued for someone with no device');

create temp table claimed on commit drop as select public.claim_push_batch() as batch;
select is(jsonb_array_length((select batch from claimed)), 1, 'the sender claims the due push');
select is(jsonb_array_length((select batch -> 0 -> 'devices' from claimed)), 2, 'with all of the recipient''s devices');
select is((select batch -> 0 ->> 'badge' from claimed), '1', 'and their unread count as the badge');
select is((select batch -> 0 ->> 'kind' from claimed), 'friend_request', 'and the kind');
select is(jsonb_array_length(public.claim_push_batch()), 0, 'a claimed push is not handed out twice');
select public.finish_push(((select batch -> 0 ->> 'id' from claimed))::bigint, 'sent');
select ok((select sent_at is not null from public.push_outbox where recipient_id = tests.who('alice')), 'finishing records it as sent');

-- ------------------------------------------------------------ take replies ---

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
  )),
  null, false, null, false
);

select tests.act_as_admin();
insert into tests.fx (k, v) select 'take', gen_random_uuid();
insert into public.prompt_comments (id, post_id, author_id, body, posted_with_pick)
select v, tests.who('post'), tests.who('alice'), 'my take', true from tests.fx where k = 'take';

select tests.act_as(tests.who('bob'));
select prompts.post_comment(tests.who('post'), 'reply one', tests.who('take'));
select tests.act_as(tests.who('cara'));
select prompts.post_comment(tests.who('post'), 'reply two', tests.who('take'));
select tests.act_as_admin();
select is((select count(*)::integer from public.push_outbox where recipient_id = tests.who('alice') and kind = 'take_reply'), 1,
  'several replies to one take queue a single push');
select ok((select available_at > now() + interval '20 seconds' from public.push_outbox where kind = 'take_reply'),
  'which waits a moment so a burst stays one');
select is(jsonb_array_length(public.claim_push_batch()), 0, 'and is not claimable before then');

update public.push_outbox set available_at = now() where kind = 'take_reply';
select is(jsonb_array_length(public.claim_push_batch()), 1, 'it goes out once due');
select public.finish_push((select id from public.push_outbox where kind = 'take_reply'), 'sent');

-- A reply after the owner has read the item is a new alert.
select tests.act_as(tests.who('alice'));
select public.mark_all_notifications_read();
select tests.act_as(tests.who('bob'));
select prompts.post_comment(tests.who('post'), 'reply three', tests.who('take'));
select tests.act_as_admin();
select is((select count(*)::integer from public.push_outbox where kind = 'take_reply' and sent_at is null), 1,
  'a reply after the item was read queues a new push');

-- Reading it before the push goes out cancels it: the inbox is the truth.
select tests.act_as(tests.who('alice'));
select public.mark_all_notifications_read();
select tests.act_as_admin();
update public.push_outbox set available_at = now() where sent_at is null and kind = 'take_reply';
select is(jsonb_array_length(public.claim_push_batch()), 0, 'a push for an item already read is dropped');
select is((select last_error from public.push_outbox where kind = 'take_reply' order by id desc limit 1), 'suppressed: not_unread',
  'and says why');

-- ---------------------------------------------------------------- blocking ---

select tests.act_as(tests.who('alice'));
select public.mark_all_notifications_read();
select tests.act_as(tests.who('cara'));
select prompts.post_comment(tests.who('post'), 'cara again', tests.who('take'));
select tests.act_as(tests.who('alice'));
select public.block_user(tests.who('cara'));
select tests.act_as_admin();
update public.push_outbox set available_at = now() where sent_at is null and dead_at is null;
select is(jsonb_array_length(public.claim_push_batch()), 0, 'a block placed after queueing still stops the push');
select is((select last_error from public.push_outbox where kind = 'take_reply' order by id desc limit 1), 'suppressed: blocked',
  'and says why');

select tests.act_as(tests.who('cara'));
select prompts.post_comment(tests.who('post'), 'cara blocked', tests.who('take'));
select tests.act_as_admin();
select is((select count(*)::integer from public.push_outbox where kind = 'take_reply' and sent_at is null and dead_at is null), 0,
  'a blocked player''s reply never queues a push');

-- ------------------------------------------------------------ room invites ---

select tests.act_as(tests.who('alice'));
select public.accept_friend_request(tests.who('bob'));
select tests.mklobby(array[tests.who('alice')]) as lobby \gset
select tests.act_as(tests.who('alice'));
select public.invite_friend_to_room(:'lobby'::uuid, tests.who('bob'));
select tests.act_as_admin();
select is((select count(*)::integer from public.push_outbox where recipient_id = tests.who('bob') and kind = 'room_invite'), 1,
  'a room invite queues a push for the invitee');
select ok((select item_key like 'i:%' from public.push_outbox where kind = 'room_invite'), 'for the invite item');

update public.room_invites set created_at = now() - interval '25 hours';
select is(jsonb_array_length(public.claim_push_batch()), 0, 'an invite that expired before sending is not pushed');
select is((select last_error from public.push_outbox where kind = 'room_invite'), 'suppressed: not_unread', 'and says why');

-- -------------------------------------------------------------- new prompt ---

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post2', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
  ))
);
select tests.act_as_admin();
select is((select count(*)::integer from public.push_outbox where kind = 'new_prompt' and post_id = tests.who('post2')), 3,
  'a new prompt queues a push for every user with a device');
select is((select count(*)::integer from public.push_outbox where kind = 'new_prompt' and recipient_id in (tests.who('admin'), tests.who('dave'))), 0,
  'except its author and people with no device');
select is((select count(*)::integer from public.push_outbox where kind = 'new_prompt' and post_id = tests.who('post')), 0,
  'and not when the admin chose to skip the push');

select is(jsonb_array_length(public.claim_push_batch(2)), 2, 'the sender can take a batch at a time');
select is(jsonb_array_length(public.claim_push_batch(10)), 1, 'and the rest after');

update public.prompt_posts set lock_at = now() - interval '1 minute' where id = tests.who('post2');
update public.push_outbox set claimed_at = null, available_at = now() where kind = 'new_prompt';
select is(jsonb_array_length(public.claim_push_batch()), 0, 'a prompt that locked before sending is not pushed');

-- -------------------------------------------------------------- outcomes ---

select tests.act_as_admin();
insert into public.push_outbox (recipient_id, kind, ref_id, item_key, attempts)
values (tests.who('alice'), 'friend_request', gen_random_uuid(), 'n:x', 1);
select public.finish_push((select max(id) from public.push_outbox), 'retry', 'timeout');
select ok((select claimed_at is null and available_at > now() and last_error = 'timeout' and dead_at is null from public.push_outbox where id = (select max(id) from public.push_outbox)),
  'a retry releases the push and waits');
update public.push_outbox set attempts = 5 where id = (select max(id) from public.push_outbox);
select public.finish_push((select max(id) from public.push_outbox), 'retry', 'timeout');
select ok((select dead_at is not null from public.push_outbox where id = (select max(id) from public.push_outbox)), 'a fifth failed attempt gives up');
select public.finish_push((select max(id) from public.push_outbox), 'dead', 'BadDeviceToken');
select is((select last_error from public.push_outbox where id = (select max(id) from public.push_outbox)), 'BadDeviceToken', 'a dead push records why');

-- ------------------------------------------------------------------ access ---

select tests.act_as(tests.who('alice'));
-- The seed grants SELECT on every public table, so RLS (no policy) is what hides the rows.
select is((select count(*)::integer from public.push_outbox), 0, 'clients cannot read the outbox');
select throws_ok($$ select public.claim_push_batch() $$, '42501', null, 'clients cannot claim pushes');
select throws_ok($$ select public.finish_push(1, 'sent') $$, '42501', null, 'or finish them');

-- A broken outbox must never fail the action behind it.
select tests.act_as_admin();
alter table public.push_outbox rename to push_outbox_broken;
select tests.act_as(tests.who('cara'));
select lives_ok($$ select public.send_friend_request('PoBob') $$, 'a failing push queue does not fail the friend request');
select tests.act_as_admin();
select is((select count(*)::integer from public.notifications where recipient_id = tests.who('bob') and type = 'friend_request'), 1,
  'the inbox row is still written');
alter table public.push_outbox_broken rename to push_outbox;

select * from finish();
rollback;
