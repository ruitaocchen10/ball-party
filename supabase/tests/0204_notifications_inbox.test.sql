-- Tests for the notification inbox (0204): friend request and take reply
-- notifications written by triggers, coalescing, block suppression, room
-- invite state resolved on read, unread/read, and retention.

begin;
select plan(38);
\ir support/harness.psql

insert into tests.fx (k, v) values
  ('admin',  tests.mkuser('NiAdmin')),
  ('alice',  tests.mkuser('NiAlice')),
  ('bob',    tests.mkuser('NiBob')),
  ('cara',   tests.mkuser('NiCara')),
  ('guest',  tests.mkguest('NiGuest'));

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

-- ------------------------------------------------------- friend requests ---

select tests.act_as(tests.who('alice'));
select public.send_friend_request('NiBob');

select tests.act_as(tests.who('bob'));
select is((select count(*)::integer from public.list_inbox() where kind = 'friend_request'), 1, 'a friend request lands in the addressee''s inbox');
select is((select state from public.list_inbox() where kind = 'friend_request'), 'pending', 'it is pending');
select is((select actor_id from public.list_inbox() where kind = 'friend_request'), tests.who('alice'), 'the actor is the requester');
select is(public.inbox_unread_count(), 1, 'it counts as unread');

select tests.act_as(tests.who('alice'));
select is((select count(*)::integer from public.list_inbox()), 0, 'the requester sees nothing');

-- Accepting resolves the item rather than removing it.
select tests.act_as(tests.who('bob'));
select public.accept_friend_request(tests.who('alice'));
select is((select state from public.list_inbox() where kind = 'friend_request'), 'accepted', 'an accepted request shows as accepted');

select is(public.mark_notification_read((select item_key from public.list_inbox() where kind = 'friend_request')), true, 'it can be marked read');
select is(public.inbox_unread_count(), 0, 'reading it clears the badge');
select is(public.mark_notification_read((select item_key from public.list_inbox() where kind = 'friend_request')), false, 'marking it again changes nothing');

-- Declining deletes the friendships row, so the item disappears.
select tests.act_as(tests.who('cara'));
select public.send_friend_request('NiBob');
select tests.act_as(tests.who('bob'));
select is((select count(*)::integer from public.list_inbox() where kind = 'friend_request' and actor_id = tests.who('cara')), 1, 'a second request shows up');
select public.decline_friend_request(tests.who('cara'));
select is((select count(*)::integer from public.list_inbox() where actor_id = tests.who('cara')), 0, 'a declined request leaves the inbox');
select tests.act_as(tests.who('cara'));
select public.send_friend_request('NiBob');
select tests.act_as(tests.who('bob'));
select is((select count(*)::integer from public.list_inbox() where actor_id = tests.who('cara')), 1, 'asking again after a decline notifies again');
select is(public.inbox_unread_count(), 1, 'and counts as unread');

-- Asking back auto-accepts and must not notify the original requester.
select tests.act_as(tests.who('bob'));
select public.send_friend_request('NiCara');
select tests.act_as(tests.who('cara'));
select is((select count(*)::integer from public.list_inbox() where kind = 'friend_request'), 0, 'an auto-accepted request does not notify the original requester');

-- ------------------------------------------------------------ take replies ---

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
  ))
);

-- Alice's take (a comment posted with a pick), written as owner.
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'take', gen_random_uuid();
insert into public.prompt_comments (id, post_id, author_id, body, posted_with_pick)
select v, tests.who('post'), tests.who('alice'), 'my take', true from tests.fx where k = 'take';

select tests.act_as(tests.who('bob'));
select prompts.post_comment(tests.who('post'), 'reply one', tests.who('take'));
select tests.act_as(tests.who('alice'));
select is((select count(*)::integer from public.list_inbox() where kind = 'take_reply'), 1, 'a reply to your take notifies you');
select is((select reply_count from public.list_inbox() where kind = 'take_reply'), 1, 'with a count of one');
select is((select post_id from public.list_inbox() where kind = 'take_reply'), tests.who('post'), 'and points at the post');
select is((select ref_id from public.list_inbox() where kind = 'take_reply'), tests.who('take'), 'and at the take');

select tests.act_as(tests.who('cara'));
select prompts.post_comment(tests.who('post'), 'reply two', tests.who('take'));
select tests.act_as(tests.who('alice'));
select is((select count(*)::integer from public.list_inbox() where kind = 'take_reply'), 1, 'more replies coalesce into one item');
select is((select reply_count from public.list_inbox() where kind = 'take_reply'), 2, 'and the count goes up');
select is((select actor_id from public.list_inbox() where kind = 'take_reply'), tests.who('cara'), 'and the actor is the latest replier');

select public.mark_all_notifications_read();
select is(public.inbox_unread_count(), 0, 'mark all read clears everything');
select tests.act_as(tests.who('bob'));
select prompts.post_comment(tests.who('post'), 'reply three', tests.who('take'));
select tests.act_as(tests.who('alice'));
select is((select reply_count from public.list_inbox() where kind = 'take_reply'), 1, 'after reading, the count starts over');
select is((select is_unread from public.list_inbox() where kind = 'take_reply'), true, 'and the item is unread again');

-- Replying to your own take does not notify you.
select prompts.post_comment(tests.who('post'), 'my own reply', tests.who('take'));
select is((select reply_count from public.list_inbox() where kind = 'take_reply'), 1, 'replying to yourself adds nothing');

-- A top-level comment is not a reply.
select tests.act_as(tests.who('bob'));
select prompts.post_comment(tests.who('post'), 'top level', null);
select tests.act_as(tests.who('alice'));
select is((select reply_count from public.list_inbox() where kind = 'take_reply'), 1, 'a top-level comment notifies nobody');

-- --------------------------------------------------------------- blocking ---

-- Alice blocks bob: his earlier reply stops showing, and new ones do not notify.
select public.mark_all_notifications_read();
select public.block_user(tests.who('bob'));
select tests.act_as(tests.who('cara'));
select prompts.post_comment(tests.who('post'), 'cara again', tests.who('take'));
select tests.act_as(tests.who('bob'));
select prompts.post_comment(tests.who('post'), 'bob after block', tests.who('take'));
select tests.act_as(tests.who('alice'));
select is((select actor_id from public.list_inbox() where kind = 'take_reply'), tests.who('cara'), 'a blocked player''s reply does not take over the item');
select is((select reply_count from public.list_inbox() where kind = 'take_reply'), 1, 'and is not counted');

-- ------------------------------------------------------------ room invites ---

select tests.act_as(tests.who('cara'));
select public.send_friend_request('NiAlice');
select tests.act_as(tests.who('alice'));
select public.accept_friend_request(tests.who('cara'));
select tests.mklobby(array[tests.who('alice')]) as lobby \gset
select tests.act_as(tests.who('alice'));
select public.invite_friend_to_room(:'lobby'::uuid, tests.who('cara'));

select tests.act_as(tests.who('cara'));
select is((select state from public.list_inbox() where kind = 'room_invite'), 'pending', 'a live room invite shows as pending');
select is((select is_unread from public.list_inbox() where kind = 'room_invite'), true, 'and counts as unread');
select is(public.inbox_unread_count(), 1, 'the badge includes it');

select tests.act_as_admin();
update public.room_invites set created_at = now() - interval '25 hours';
select tests.act_as(tests.who('cara'));
select is((select state from public.list_inbox() where kind = 'room_invite'), 'expired', 'an invite past 24 hours shows as expired');
select is(public.inbox_unread_count(), 0, 'and no longer counts as unread');

select tests.act_as_admin();
update public.room_invites set created_at = now() - interval '4 days';
select tests.act_as(tests.who('cara'));
select is((select count(*)::integer from public.list_inbox() where kind = 'room_invite'), 0, 'an old invite drops out after three days');

-- ------------------------------------------------- access and retention ---

select tests.act_as(tests.who('alice'));
select is((select count(*)::integer from public.notifications where recipient_id <> tests.who('alice')), 0, 'the table only shows the caller their own rows');
select throws_ok($$ insert into public.notifications (recipient_id, type, actor_id, ref_id) values (gen_random_uuid(), 'take_reply', gen_random_uuid(), gen_random_uuid()) $$,
  '42501', null, 'clients cannot write the table');

select tests.act_as_guest(tests.who('guest'));
select is((select count(*)::integer from public.list_inbox()), 0, 'a guest gets an empty inbox, not an error');

select tests.act_as_admin();
update public.notifications set read_at = now() - interval '31 days' where recipient_id = tests.who('alice');
select private.prune_notifications();
select is((select count(*)::integer from public.notifications where recipient_id = tests.who('alice')), 0, 'read items are pruned after 30 days');

select * from finish();
rollback;
