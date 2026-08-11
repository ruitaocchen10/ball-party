begin;
select plan(17);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('guest', tests.mkguest('Devin'));

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select is(
  (select display_name from public.profiles where id = (select v from tests.fx where k = 'guest')),
  'Devin',
  'a guest receives the display name supplied at anonymous sign-in'
);

select is(
  (select is_guest from public.profiles where id = (select v from tests.fx where k = 'guest')),
  true,
  'a guest profile is marked for the room roster'
);

select throws_ok(
  format($$ update public.profiles set is_guest = false where id = %L $$, (select v from tests.fx where k = 'guest')),
  '42501', null,
  'a guest cannot forge the roster marker'
);

select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'lobby', public.create_lobby().id;

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select lives_ok(
  format($$ select public.join_lobby(%L) $$, (select code from public.lobbies where id = (select v from tests.fx where k = 'lobby'))),
  'a guest can join a room'
);

select is(
  (select display_name from public.profiles where id = (select v from tests.fx where k = 'host')),
  'Ava',
  'a guest can see a co-player name'
);

select throws_ok(
  'select public.create_lobby()', '42501', 'not_authenticated',
  'a guest cannot create a room'
);

select tests.act_as_admin();
update public.lobbies set host_id = (select v from tests.fx where k = 'guest')
 where id = (select v from tests.fx where k = 'lobby');
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok(
  format($$ select public.start_run(%L, 'arcade', 'auction_team_builder') $$, (select v from tests.fx where k = 'lobby')),
  '42501', 'not_authenticated',
  'the retained run-start guard still rejects a guest'
);

select tests.act_as_admin();
update public.lobbies set host_id = (select v from tests.fx where k = 'host')
 where id = (select v from tests.fx where k = 'lobby');
select tests.act_as((select v from tests.fx where k = 'host'));
insert into tests.fx (k, v)
select 'match', public.start_run((select v from tests.fx where k = 'lobby'), 'arcade', 'auction_team_builder').id;

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select lives_ok(
  format($$ select public.start_auction(%L) $$, (select v from tests.fx where k = 'match')),
  'a guest can set up the match they were snapshotted into'
);

select tests.act_as_admin();
update public.auction_matches set phase = 'bidding', phase_deadline = null, turn_seat = 1,
  turn_deadline = now() + interval '20 seconds'
 where match_id = (select v from tests.fx where k = 'match');
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select lives_ok(
  format($$ select public.place_bid(%L, 1) $$, (select v from tests.fx where k = 'match')),
  'a guest can bid'
);

select tests.act_as_admin();
update public.auction_matches set turn_seat = 0, turn_deadline = now() + interval '20 seconds'
 where match_id = (select v from tests.fx where k = 'match');
select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(
  format($$ select public.pass_lot(%L) $$, (select v from tests.fx where k = 'match')),
  'a co-player can resolve a lot the guest bid on'
);
select tests.act_as_admin();
select is(
  (select winner_id from public.auction_lots where match_id = (select v from tests.fx where k = 'match') and seq = 1),
  (select v from tests.fx where k = 'guest'),
  'a guest can win a lot'
);

update public.auction_matches set current_lot = 2, phase = 'bidding', phase_deadline = null,
  turn_seat = 1, turn_deadline = now() + interval '20 seconds'
 where match_id = (select v from tests.fx where k = 'match');
select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select lives_ok(
  format($$ select public.pass_lot(%L) $$, (select v from tests.fx where k = 'match')),
  'a guest can pass'
);

select tests.act_as_admin();
select private.finish_match(
  (select v from tests.fx where k = 'match'),
  jsonb_build_object((select v from tests.fx where k = 'host')::text, 3, (select v from tests.fx where k = 'guest')::text, 8)
);
select is(
  (select score from public.run_participants rp join public.matches m on m.run_id = rp.run_id
    where m.id = (select v from tests.fx where k = 'match') and rp.user_id = (select v from tests.fx where k = 'guest')),
  8,
  'a guest score counts toward the run standings'
);

insert into tests.fx (k, v) values ('account', tests.mkuser('Morgan'));
select tests.act_as((select v from tests.fx where k = 'account'));
select lives_ok(
  format($$ select public.record_guest_account_collision(%L) $$, (select v from tests.fx where k = 'guest')),
  'signing into a separate account records the guest identity'
);
select tests.act_as_admin();
select is(
  (select account_id from public.guest_account_collisions where guest_id = (select v from tests.fx where k = 'guest')),
  (select v from tests.fx where k = 'account'),
  'the collision breadcrumb keeps both identities'
);

select tests.act_as_admin();
insert into tests.fx (k, v) values ('empty', tests.mkguest('Empty'));
update auth.users set created_at = now() - interval '31 days' where id = (select v from tests.fx where k = 'empty');
select private.cleanup_guest_accounts();
select is((select count(*)::int from auth.users where id = (select v from tests.fx where k = 'empty')), 0,
  'the cleanup removes an unplayed guest after thirty days');

select is((select count(*)::int from auth.users where id = (select v from tests.fx where k = 'guest')), 1,
  'the cleanup cannot delete a guest with run participation');

select * from finish();
rollback;
