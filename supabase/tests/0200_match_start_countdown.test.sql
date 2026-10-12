-- A group match opens with a three-second countdown owned by the server: the
-- match carries `play_starts_at`, and the first deadline the game set is
-- pushed back by the same three seconds.
begin;
select plan(16);
\ir support/harness.psql

-- ------------------------------------------------------------------ auction --

insert into tests.fx (k, v) values ('auction', tests.mkmatch(2, 'auction_team_builder'));
select auction.start((select v from tests.fx where k = 'auction'), 'weekly', 'standard');
select tests.act_as_admin();

select ok((select play_starts_at from public.matches where id = (select v from tests.fx where k = 'auction'))
  between now() + interval '2 seconds' and now() + interval '4 seconds',
  'a group auction starts playing three seconds after the host presses start');
select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'auction')),
  'lot_preview', 'it still opens on the lot preview');
select ok((select phase_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'auction'))
  between now() + interval '7 seconds' and now() + interval '9 seconds',
  'and the preview runs its full five seconds after the countdown');

-- ------------------------------------------------------------ higher or lower --

insert into tests.fx (k, v) values ('hol', tests.mkmatch(2, 'higher_or_lower'));
select higher_or_lower.start((select v from tests.fx where k = 'hol'));
select tests.act_as_admin();
select ok((select play_starts_at from public.matches where id = (select v from tests.fx where k = 'hol'))
  between now() + interval '2 seconds' and now() + interval '4 seconds',
  'a group Higher or Lower gets the same start time');
select ok((select phase_deadline from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'hol'))
  between now() + interval '7 seconds' and now() + interval '9 seconds',
  'and its board intro starts after the countdown');

-- --------------------------------------------------------------- wavelength --

insert into tests.fx (k, v) values ('wave', tests.mkmatch(2, 'wavelength_2v2'));
select wavelength.start((select v from tests.fx where k = 'wave'), 'coop', 'short');
select tests.act_as_admin();
select ok((select play_starts_at from public.matches where id = (select v from tests.fx where k = 'wave'))
  between now() + interval '2 seconds' and now() + interval '4 seconds',
  'a Wavelength match gets the same start time');
select ok((select phase_deadline from public.wavelength_matches where match_id = (select v from tests.fx where k = 'wave'))
  > (select play_starts_at from public.matches where id = (select v from tests.fx where k = 'wave')),
  'and its first clock starts after the countdown');

-- ------------------------------------------------------------------- replay --

select private.finish_match(
  (select v from tests.fx where k = 'auction'),
  (select jsonb_object_agg(user_id::text, 1) from public.run_participants
    where run_id = (select run_id from public.matches where id = (select v from tests.fx where k = 'auction')))
);
select tests.act_as((select host_id from public.lobbies where id = (
  select lobby_id from public.runs where id = (select run_id from public.matches where id = (select v from tests.fx where k = 'auction')))));
insert into tests.fx (k, v) select 'replay', next_match_id
  from public.choose_post_game((select v from tests.fx where k = 'auction'), 'replay');
select tests.act_as_admin();
select ok((select play_starts_at from public.matches where id = (select v from tests.fx where k = 'replay'))
  between now() + interval '2 seconds' and now() + interval '4 seconds',
  'a replay counts down like a fresh start');
select ok((select phase_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'replay'))
  between now() + interval '7 seconds' and now() + interval '9 seconds',
  'and its first lot preview is full-length after it');

-- --------------------------------------------------------------------- solo --

insert into tests.fx (k, v) values ('ava', tests.mkuser('ava'));
select tests.act_as((select v from tests.fx where k = 'ava'));
insert into tests.fx (k, v) select 'solo', (public.start_solo_run('higher_or_lower')).id;
select higher_or_lower.start((select v from tests.fx where k = 'solo'));
select tests.act_as_admin();
select is((select play_starts_at from public.matches where id = (select v from tests.fx where k = 'solo')), null,
  'a solo run has no countdown');

-- --------------------------------------------------------------------- read --

select tests.act_as((select user_id from public.run_participants where run_id = (
  select run_id from public.matches where id = (select v from tests.fx where k = 'auction')) order by seat limit 1));
select is((public.match_play_start((select v from tests.fx where k = 'auction')) ->> 'play_starts_at') is not null, true,
  'a participant can read when play starts');
select is((public.match_play_start((select v from tests.fx where k = 'auction')) ->> 'server_now') is not null, true,
  'along with the server clock to count it down against');

insert into tests.fx (k, v) values ('stranger', tests.mkuser('sten'));
select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(format($$ select public.match_play_start(%L) $$, (select v from tests.fx where k = 'auction')),
  '42501', 'not_a_participant', 'someone outside the match cannot read it');
select tests.act_as_admin();
select throws_ok(format($$ select public.match_play_start(%L) $$, (select v from tests.fx where k = 'auction')),
  '42501', 'not_authenticated', 'nor can a caller with no session');
select ok(not has_function_privilege('anon', 'public.match_play_start(uuid)', 'execute'),
  'anonymous callers cannot call it');
select ok(not has_function_privilege('authenticated', 'private.begin_match_countdown(uuid)', 'execute'),
  'and the countdown helper is not callable from outside');

select * from finish();
rollback;
