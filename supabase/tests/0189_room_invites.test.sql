begin;
select plan(28);

\ir support/harness.psql

insert into tests.fx (k, v) values
  ('host',     tests.mkuser('RiHost')),
  ('f1',       tests.mkuser('RiOne')),
  ('f2',       tests.mkuser('RiTwo')),
  ('f3',       tests.mkuser('RiThree')),
  ('f4',       tests.mkuser('RiFour')),
  ('f5',       tests.mkuser('RiFive')),
  ('stranger', tests.mkuser('RiStranger')),
  ('guest',    tests.mkguest('RiGuest'));

-- host is friends with f1..f5 (each asks, host accepts).
do $$
declare who text;
begin
  foreach who in array array['f1', 'f2', 'f3', 'f4', 'f5'] loop
    perform tests.act_as((select fx.v from tests.fx where fx.k = who));
    perform public.send_friend_request('RiHost');
    perform tests.act_as((select fx.v from tests.fx where fx.k = 'host'));
    perform public.accept_friend_request((select fx.v from tests.fx where fx.k = who));
  end loop;
end $$;

select tests.mklobby(array[(select v from tests.fx where k = 'host')]) as lobby \gset

select tests.act_as((select v from tests.fx where k = 'host'));

-- ------------------------------------------------------------- inviting ---

select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'f1')), 'invited', 'a member can invite a friend');
select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'f1')), 'already_invited', 'inviting twice is a no-op');
select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'stranger')), 'unavailable', 'a non-friend cannot be invited');
select is(public.invite_friend_to_room(:'lobby'::uuid, gen_random_uuid()), 'unavailable', 'an unknown player cannot be invited');
select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'host')), 'unavailable', 'you cannot invite yourself');

select tests.act_as((select v from tests.fx where k = 'f2'));
select throws_ok(
  format($$ select public.invite_friend_to_room(%L, %L) $$, :'lobby', (select v from tests.fx where k = 'host')),
  '42501', 'not_a_room_member',
  'only a member of the room can invite'
);

-- -------------------------------------------------------------- listing ---

select tests.act_as((select v from tests.fx where k = 'f1'));
select is(
  (select (sender_username, member_count)::text from public.list_room_invites()),
  '(RiHost,1)',
  'the friend sees the invite with the sender and room size'
);
select tests.act_as((select v from tests.fx where k = 'stranger'));
select is((select count(*)::integer from public.list_room_invites()), 0, 'someone else sees no invites');
select is((select count(*)::integer from public.room_invites), 0, 'the table is not readable around the RPCs');

-- ------------------------------------------------------------- accepting ---

select tests.act_as((select v from tests.fx where k = 'f1'));
select list_room_invites.invite_id as inv1 from public.list_room_invites() \gset
select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select public.accept_room_invite(%L) $$, :'inv1'),
  'P0001', 'invite_not_found',
  'only the recipient can accept an invite'
);
select tests.act_as((select v from tests.fx where k = 'f1'));
select is((public.accept_room_invite(:'inv1'::uuid)).id, :'lobby'::uuid, 'accepting returns the room');
select tests.act_as_admin();
select is(
  (select count(*)::integer from public.lobby_members
    where lobby_id = :'lobby'::uuid and user_id = (select v from tests.fx where k = 'f1') and left_at is null),
  1,
  'accepting joins the room through join_lobby'
);
select tests.act_as((select v from tests.fx where k = 'f1'));
select is((select count(*)::integer from public.list_room_invites()), 0, 'an accepted invite leaves the list');
select throws_ok(
  format($$ select public.accept_room_invite(%L) $$, :'inv1'),
  'P0001', 'invite_not_found',
  'an invite cannot be accepted twice'
);
select tests.act_as((select v from tests.fx where k = 'host'));
select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'f1')), 'already_in_room', 'a friend already in the room is not re-invited');

-- -------------------------------------------------------------- declining ---

select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'f2')), 'invited', 'host invites f2');
select tests.act_as((select v from tests.fx where k = 'f2'));
select list_room_invites.invite_id as inv2 from public.list_room_invites() \gset
select is(public.decline_room_invite(:'inv2'::uuid), true, 'the recipient can decline');
select is(public.decline_room_invite(:'inv2'::uuid), false, 'declining twice is a no-op');
select is((select count(*)::integer from public.list_room_invites()), 0, 'a declined invite leaves the list');
select tests.act_as((select v from tests.fx where k = 'host'));
select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'f2')), 'invited', 'a declined friend can be invited again');

-- ------------------------------------------------- invites that go stale ---

select is(public.invite_friend_to_room(:'lobby'::uuid, (select v from tests.fx where k = 'f3')), 'invited', 'host invites f3');
select public.remove_friend((select v from tests.fx where k = 'f3'));
select tests.act_as((select v from tests.fx where k = 'f3'));
select is((select count(*)::integer from public.list_room_invites()), 0, 'an invite from someone who is no longer a friend is not shown');

select tests.act_as((select v from tests.fx where k = 'host'));
select public.close_lobby(:'lobby'::uuid);
select tests.act_as((select v from tests.fx where k = 'f2'));
select is((select count(*)::integer from public.list_room_invites()), 0, 'invites to a closed room are not shown');
select throws_ok(
  format($$ select public.accept_room_invite(%L) $$, (select id from public.room_invites where recipient_id = (select v from tests.fx where k = 'f2') limit 1)),
  'P0001', 'invite_not_found',
  'an invite to a closed room cannot be accepted'
);

-- ------------------------------------------------------------- room full ---

select tests.act_as_admin();
select tests.mklobby(array[
  (select v from tests.fx where k = 'host'), (select v from tests.fx where k = 'f1'),
  (select v from tests.fx where k = 'f2'), (select v from tests.fx where k = 'f4')]) as full_lobby \gset
select tests.act_as((select v from tests.fx where k = 'host'));
select is(public.invite_friend_to_room(:'full_lobby'::uuid, (select v from tests.fx where k = 'f5')), 'room_full', 'a full room cannot take another invite');

-- ---------------------------------------------------------------- guests ---

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok($$ select * from public.list_room_invites() $$, '42501', 'guests_cannot_have_friends', 'a guest has no invites');

-- ---------------------------------------------------------- rate limiting ---

select tests.act_as((select v from tests.fx where k = 'f4'));
select lives_ok(
  format($$ select public.invite_friend_to_room(%L, gen_random_uuid()) from generate_series(1, 60) $$, :'full_lobby'),
  'sixty invites an hour are allowed'
);
select throws_ok(
  format($$ select public.invite_friend_to_room(%L, gen_random_uuid()) $$, :'full_lobby'),
  '54000', 'rate_limited',
  'the next invite in the hour is refused'
);

select * from finish();
rollback;
