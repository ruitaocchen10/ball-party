-- The Broadcast authorization for Wavelength is deliberately separate from
-- table-change Realtime: it protects an ephemeral client message, not a row.

begin;
select plan(6);

\ir support/harness.psql

select ok(
  exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname = 'wavelength_needle_receive_member' and cmd = 'SELECT'),
  'match members may receive live-needle broadcasts'
);
select ok(
  exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname = 'wavelength_needle_send_active_guesser' and cmd = 'INSERT'),
  'the active guesser may publish live-needle broadcasts'
);
select is(
  (select count(*)::int from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname in ('wavelength_needle_receive_member', 'wavelength_needle_send_active_guesser')),
  2,
  'only the two narrowly-scoped Wavelength Broadcast policies exist'
);
select ok(
  (select qual from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname = 'wavelength_needle_receive_member') like '%wavelength_players%',
  'receiving is checked against match membership'
);
select ok(
  (select with_check from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname = 'wavelength_needle_send_active_guesser') like '%guesser_id%',
  'sending is limited to the current round guesser'
);
select ok(
  (select with_check from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname = 'wavelength_needle_send_active_guesser') like '%wm.phase = ''guess''%',
  'sending closes when the guess phase ends'
);

select * from finish();
rollback;
