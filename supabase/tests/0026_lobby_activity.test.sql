-- Durable lobby membership is distinct from the short-lived activity lease.
begin;
select plan(13);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('host', tests.mkuser('Ava')), ('member', tests.mkuser('Bo')),
       ('stranger', tests.mkuser('Cy'));

insert into tests.fx (k, v)
values ('lobby', tests.mklobby(array[
  (select v from tests.fx where k = 'host'),
  (select v from tests.fx where k = 'member')
]));

select tests.act_as((select v from tests.fx where k = 'member'));
select lives_ok(
  format($$ select public.heartbeat_lobby(%L) $$, (select v from tests.fx where k = 'lobby')),
  'a current member can renew their activity lease'
);

select tests.act_as_admin();
select ok(
  (select last_seen_at > now() - interval '5 seconds'
     from public.lobby_members
    where lobby_id = (select v from tests.fx where k = 'lobby')
      and user_id = (select v from tests.fx where k = 'member')),
  'the heartbeat records the member as recently active'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select public.heartbeat_lobby(%L) $$, (select v from tests.fx where k = 'lobby')),
  'P0001', 'not_a_member',
  'a stranger cannot create activity in a room'
);

select tests.act_as((select v from tests.fx where k = 'member'));
select ok(
  public.lobby_host_is_active((select v from tests.fx where k = 'lobby')),
  'the host starts with a live activity lease'
);
select throws_ok(
  format($$ select public.claim_lobby_host(%L) $$, (select v from tests.fx where k = 'lobby')),
  'P0001', 'host_still_active',
  'a connected member cannot take over during the host grace period'
);

select tests.act_as_admin();
update public.lobby_members
   set last_seen_at = now() - interval '31 seconds'
 where lobby_id = (select v from tests.fx where k = 'lobby')
   and user_id = (select v from tests.fx where k = 'host');

select tests.act_as((select v from tests.fx where k = 'member'));
select ok(
  not public.lobby_host_is_active((select v from tests.fx where k = 'lobby')),
  'the activity read expires when the host has been away for thirty seconds'
);
select lives_ok(
  format($$ select public.claim_lobby_host(%L) $$, (select v from tests.fx where k = 'lobby')),
  'a member can take host controls after the grace period'
);

select tests.act_as_admin();
select is(
  (select host_id from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  (select v from tests.fx where k = 'member'),
  'takeover permanently transfers the host role'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(
  format($$ select public.heartbeat_lobby(%L) $$, (select v from tests.fx where k = 'lobby')),
  'the former host can return as a regular member'
);

select tests.act_as_admin();
select is(
  (select host_id from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  (select v from tests.fx where k = 'member'),
  'the returning former host does not reclaim controls'
);

-- A fresh room with no active members is closed by the independent lobby sweep.
insert into tests.fx (k, v)
values ('idle_lobby', tests.mklobby(array[(select v from tests.fx where k = 'stranger')]));

select tests.act_as_admin();
update public.lobby_members
   set last_seen_at = now() - interval '21 minutes'
 where lobby_id = (select v from tests.fx where k = 'idle_lobby');
select private.sweep_inactive_lobbies();

select ok(
  (select closed_at is not null from public.lobbies where id = (select v from tests.fx where k = 'idle_lobby')),
  'the sweep closes a room after every member has been inactive for twenty minutes'
);

select ok(
  (select closed_at is null from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  'activity from any current member keeps the room open'
);

select tests.act_as((select v from tests.fx where k = 'member'));
select throws_ok(
  format($$ select public.claim_lobby_host(%L) $$, (select v from tests.fx where k = 'idle_lobby')),
  'P0001', 'lobby_not_found',
  'a closed lobby cannot be taken over'
);

select * from finish();
rollback;
