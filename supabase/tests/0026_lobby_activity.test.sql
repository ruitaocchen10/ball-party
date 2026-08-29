-- Durable lobby membership is distinct from the short-lived activity lease.
begin;
select plan(8);

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

-- A game has its own abandonment janitor, so lobby cleanup must leave it alone
-- even when every lobby heartbeat is stale.
select tests.act_as((select v from tests.fx where k = 'host'));
select public.start_run((select v from tests.fx where k = 'lobby'), 'arcade', 'auction_team_builder');
select tests.act_as_admin();
update public.lobby_members
   set last_seen_at = now() - interval '21 minutes'
 where lobby_id = (select v from tests.fx where k = 'lobby');
select private.sweep_inactive_lobbies();
select ok(
  (select closed_at is null from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  'the lobby sweep leaves an active run to the match janitor'
);

select tests.act_as((select v from tests.fx where k = 'host'));
select public.leave_lobby((select v from tests.fx where k = 'lobby'));
select tests.act_as_admin();
select ok(
  (select closed_at is not null from public.lobbies where id = (select v from tests.fx where k = 'lobby')),
  'the room closes when its fixed host leaves'
);
select is(
  (select status::text from public.runs where lobby_id = (select v from tests.fx where k = 'lobby')),
  'abandoned',
  'closing the host-owned room abandons its active run'
);

select * from finish();
rollback;
