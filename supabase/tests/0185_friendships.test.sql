begin;
select plan(81);

\ir support/harness.psql

insert into tests.fx (k, v) values
  ('ann',   tests.mkuser('FzAnn')),
  ('ben',   tests.mkuser('FzBen')),
  ('cy',    tests.mkuser('FzCy')),
  ('dee',   tests.mkuser('FzDee')),
  ('rate',  tests.mkuser('FzRate')),
  ('guest', tests.mkguest('FzGuest'));

-- ---------------------------------------------------- request -> accept ----

select tests.act_as((select v from tests.fx where k = 'ann'));
select is(public.send_friend_request('fzben'), 'requested', 'a request by username (any case) is sent');
select is(public.send_friend_request('FzBen'), 'already_requested', 'asking twice is a no-op');
select is(public.send_friend_request('FzAnn'), 'unavailable', 'you cannot friend yourself');
select is(public.send_friend_request('nobody_fz'), 'unavailable', 'an unknown username is unavailable');
select is(public.send_friend_request('x'), 'unavailable', 'a malformed username is unavailable');
select is(
  (select (direction, username)::text from public.list_friend_requests()),
  '(outgoing,FzBen)',
  'the sender sees an outgoing request'
);

select tests.act_as((select v from tests.fx where k = 'ben'));
select is(
  (select (direction, username)::text from public.list_friend_requests()),
  '(incoming,FzAnn)',
  'the addressee sees an incoming request'
);
select is(public.accept_friend_request((select v from tests.fx where k = 'cy')), false, 'accepting a request that does not exist changes nothing');
select is(public.accept_friend_request((select v from tests.fx where k = 'ann')), true, 'the addressee can accept');
select is(public.accept_friend_request((select v from tests.fx where k = 'ann')), false, 'accepting twice is a no-op');
select is((select username from public.list_friends()), 'FzAnn', 'friendship is mutual: ben lists ann');
select is(public.send_friend_request('FzAnn'), 'already_friends', 'asking an existing friend says so');
select tests.act_as_admin();
select is(private.are_friends((select v from tests.fx where k = 'ann'), (select v from tests.fx where k = 'ben')), true, 'are_friends is true for friends');
select is(private.are_friends((select v from tests.fx where k = 'ben'), (select v from tests.fx where k = 'ann')), true, 'are_friends is symmetric');
select is(private.are_friends((select v from tests.fx where k = 'ann'), (select v from tests.fx where k = 'cy')), false, 'are_friends is false for strangers');

select tests.act_as((select v from tests.fx where k = 'ann'));
select is((select username from public.list_friends()), 'FzBen', 'friendship is mutual: ann lists ben');
select is((select count(*)::integer from public.list_friend_requests()), 0, 'no requests remain once accepted');

-- ------------------------------------------------- decline / cancel -------

select is(public.send_friend_request('FzCy'), 'requested', 'ann asks cy');
select tests.act_as((select v from tests.fx where k = 'cy'));
select is(public.decline_friend_request((select v from tests.fx where k = 'ann')), true, 'the addressee can decline');
select is(public.decline_friend_request((select v from tests.fx where k = 'ann')), false, 'declining twice is a no-op');
select is((select count(*)::integer from public.list_friends()), 0, 'declining does not create a friendship');

select tests.act_as((select v from tests.fx where k = 'ann'));
select is(public.send_friend_request('FzCy'), 'requested', 'a declined request can be sent again');
select is(public.cancel_friend_request((select v from tests.fx where k = 'cy')), true, 'the sender can cancel');
select is(public.cancel_friend_request((select v from tests.fx where k = 'cy')), false, 'cancelling twice is a no-op');

-- ----------------------------------------- asking back accepts a request ----

select tests.act_as((select v from tests.fx where k = 'dee'));
select is(public.send_friend_request('FzAnn'), 'requested', 'dee asks ann');
select tests.act_as((select v from tests.fx where k = 'ann'));
select is(public.send_friend_request('FzDee'), 'accepted', 'asking someone who already asked you accepts');
select is((select count(*)::integer from public.list_friends()), 2, 'ann now has two friends');

-- ---------------------------------------------------------------- remove ----

select is(public.remove_friend((select v from tests.fx where k = 'dee')), true, 'a friend can be removed');
select is(public.remove_friend((select v from tests.fx where k = 'dee')), false, 'removing twice is a no-op');
select tests.act_as((select v from tests.fx where k = 'dee'));
select is((select count(*)::integer from public.list_friends()), 0, 'removal is mutual');

-- ----------------------------------------------------------------- search ---

select tests.act_as((select v from tests.fx where k = 'cy'));
select is(
  (select (username, relationship)::text from public.search_users_by_username('fzann')),
  '(FzAnn,none)',
  'exact search (any case) finds a player'
);
select is((select count(*)::integer from public.search_users_by_username('Fz')), 0, 'a two-character query returns nothing');
select is(
  (select array_agg(username order by username) from public.search_users_by_username('FzA%')),
  null, 'wildcards return nothing'
);
select is(
  (select array_agg(username order by username) from public.search_users_by_username('fzan')),
  array['FzAnn'], 'a prefix (any case) finds players'
);
select is((select count(*)::integer from public.search_users_by_username('FzCy')), 0, 'you do not find yourself');
select is((select count(*)::integer from public.search_users_by_username('ab')), 0, 'a too-short query returns nothing');
select is(
  (select relationship from public.search_users_by_username('FzAnn')),
  'none',
  'relationship reads none for strangers'
);
select tests.act_as((select v from tests.fx where k = 'ann'));
select is(
  (select relationship from public.search_users_by_username('FzBen')),
  'friends',
  'relationship reads friends for friends'
);
select public.send_friend_request('FzCy');
select is((select relationship from public.search_users_by_username('FzCy')), 'outgoing', 'relationship reads outgoing');
select tests.act_as((select v from tests.fx where k = 'cy'));
select is((select relationship from public.search_users_by_username('FzAnn')), 'incoming', 'relationship reads incoming');
select public.decline_friend_request((select v from tests.fx where k = 'ann'));

-- ------------------------------------------------------------------ block ---

select tests.act_as((select v from tests.fx where k = 'ann'));
select is(public.block_user((select v from tests.fx where k = 'ben')), true, 'blocking a friend works');
select is((select count(*)::integer from public.list_friends()), 0, 'blocking ends the friendship');
select is((select username from public.list_blocked_users()), 'FzBen', 'the blocker lists who they blocked');
select is((select relationship from public.search_users_by_username('FzBen')), 'blocked', 'the blocker sees relationship blocked');

select tests.act_as((select v from tests.fx where k = 'ben'));
select is((select count(*)::integer from public.search_users_by_username('FzAnn')), 0, 'someone who blocked you is hidden from your search');
select is(public.send_friend_request('FzAnn'), 'unavailable', 'you cannot request someone who blocked you');
select is((select count(*)::integer from public.list_blocked_users()), 0, 'the blocked person does not see the block');
select is(public.block_user((select v from tests.fx where k = 'ann')), false, 'blocking someone who blocked you does not replace their block');
select is(public.unblock_user((select v from tests.fx where k = 'ann')), false, 'only the blocker can unblock');
select is((select count(*)::integer from public.search_users_by_username('FzAnn')), 0, 'their block still holds');

select tests.act_as((select v from tests.fx where k = 'ann'));
select is(public.unblock_user((select v from tests.fx where k = 'ben')), true, 'the blocker can unblock');
select is((select relationship from public.search_users_by_username('FzBen')), 'none', 'after unblocking they are strangers again');
select is(public.block_user((select v from tests.fx where k = 'guest')), false, 'a guest cannot be blocked');
select is(public.block_user((select v from tests.fx where k = 'ann')), false, 'you cannot block yourself');

-- ---------------------------------------------------------- invite codes ---

select tests.act_as((select v from tests.fx where k = 'ann'));
select is(length(public.get_my_friend_code()), 12, 'an invite code is 12 characters');
select is(public.get_my_friend_code(), public.get_my_friend_code(), 'the code is stable');
select public.get_my_friend_code() as old_code \gset
select public.reset_friend_code() as new_code \gset
select isnt(:'new_code'::text, :'old_code'::text, 'resetting issues a different code');
select is((select count(*)::integer from public.lookup_friend_code(:'new_code')), 0, 'you cannot look up your own code');

select tests.act_as((select v from tests.fx where k = 'cy'));
select is((select count(*)::integer from public.lookup_friend_code(:'old_code')), 0, 'a reset code no longer works');
select is(
  (select (username, relationship)::text from public.lookup_friend_code(lower(:'new_code'))),
  '(FzAnn,none)',
  'a current code names its owner, ignoring case'
);
select is(public.redeem_friend_code(:'old_code'), 'unavailable', 'redeeming a dead code is unavailable');
select is(public.redeem_friend_code('NOSUCHCODE12'), 'unavailable', 'redeeming an unknown code is unavailable');
select is(public.redeem_friend_code(:'new_code'), 'requested', 'redeeming a code sends a request');
select is(public.redeem_friend_code(:'new_code'), 'already_requested', 'redeeming twice is a no-op');
select is((select count(*)::integer from public.list_friends()), 0, 'redeeming does not befriend without acceptance');

select tests.act_as((select v from tests.fx where k = 'ann'));
select is(public.accept_friend_request((select v from tests.fx where k = 'cy')), true, 'the code owner accepts');
select public.block_user((select v from tests.fx where k = 'cy'));
select tests.act_as((select v from tests.fx where k = 'cy'));
select is((select count(*)::integer from public.lookup_friend_code(:'new_code')), 0, 'a code owner who blocked you is hidden');
select is(public.redeem_friend_code(:'new_code'), 'unavailable', 'you cannot redeem the code of someone who blocked you');

-- ------------------------------------------------------- direct table access --

select is((select count(*)::integer from public.friendships), 0, 'the table is not readable around the RPCs');
select throws_ok(
  $$ insert into public.friendships (requester_id, addressee_id, status) values (auth.uid(), gen_random_uuid(), 'accepted') $$,
  '42501', null,
  'the table cannot be written around the RPCs'
);

-- ----------------------------------------------------------------- guests ---

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok($$ select public.send_friend_request('FzAnn') $$, '42501', 'guests_cannot_have_friends', 'a guest cannot send requests');
select throws_ok($$ select * from public.list_friends() $$, '42501', 'guests_cannot_have_friends', 'a guest cannot list friends');
select throws_ok($$ select * from public.search_users_by_username('FzAnn') $$, '42501', 'guests_cannot_have_friends', 'a guest cannot search');
select throws_ok($$ select public.get_my_friend_code() $$, '42501', 'guests_cannot_have_friends', 'a guest has no invite code');

-- ---------------------------------------------------------------- deletion ---

select tests.act_as((select v from tests.fx where k = 'ann'));
select public.send_friend_request('FzBen');
select tests.act_as((select v from tests.fx where k = 'ben'));
select public.accept_friend_request((select v from tests.fx where k = 'ann'));
select public.delete_own_account();

select tests.act_as((select v from tests.fx where k = 'ann'));
select is((select count(*)::integer from public.list_friends()), 0, 'a deleted account vanishes from friend lists');
select is(public.send_friend_request('FzBen'), 'unavailable', 'a deleted account cannot be requested');
select tests.act_as_admin();
select is(
  (select count(*)::integer from public.friendships
    where (select v from tests.fx where k = 'ben') in (requester_id, addressee_id)),
  0,
  'deleting an account removes its friendships'
);

-- ------------------------------------------------------------ rate limits ---

select tests.act_as((select v from tests.fx where k = 'rate'));
select lives_ok(
  $$ select public.search_users_by_username('FzAnn') from generate_series(1, 120) $$,
  'a typing burst of searches is allowed'
);
select throws_ok(
  $$ select public.search_users_by_username('FzAnn') $$,
  '54000', 'rate_limited',
  'the 121st search in a minute is refused'
);
select lives_ok(
  $$ select public.send_friend_request('nobody_fz') from generate_series(1, 30) $$,
  'thirty requests an hour are allowed'
);
select throws_ok(
  $$ select public.send_friend_request('nobody_fz') $$,
  '54000', 'rate_limited',
  'the thirty-first request in an hour is refused, even for names that do not exist'
);

select * from finish();
rollback;
