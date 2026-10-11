-- The Higher or Lower clock is a server-owned phase machine. The browser asks
-- it to tick, but it is the deadline under this transaction's lock that says
-- whether anything changes.
begin;
select plan(18);
\ir support/harness.psql

-- A public start is the seam: it deals the board, starts its clock, and gives
-- every match member the same reconnectable state projection.
insert into tests.fx (k, v) values ('m', tests.mkmatch(2, 'higher_or_lower'));
select tests.act_as((select user_id from public.run_participants where run_id = (
  select run_id from public.matches where id = (select v from tests.fx where k = 'm')
) order by seat limit 1));
select lives_ok(
  format($$ select higher_or_lower.start(%L) $$, (select v from tests.fx where k = 'm')),
  'a participant starts the dealt ladder'
);
select is((select phase from higher_or_lower.state((select v from tests.fx where k = 'm'))), 'board_intro',
  'it opens in the shared board intro');
select ok((select phase_deadline from higher_or_lower.state((select v from tests.fx where k = 'm')))
  between now() + interval '7 seconds' and now() + interval '9 seconds',
  'and the intro carries a five-second server deadline, after the three-second start countdown');
select isnt((select server_now from higher_or_lower.state((select v from tests.fx where k = 'm'))), null,
  'state ships the server clock used to render that deadline');

-- Clients may ask early or more than once, but cannot advance a server clock.
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'board_intro', 'an early tick is a no-op');

select tests.act_as_admin();
update public.higher_or_lower_matches set phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select user_id from public.higher_or_lower_players where match_id = (select v from tests.fx where k = 'm') order by seat limit 1));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'call', 'the expired intro advances into a call');
select ok((select phase_deadline from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm'))
  between now() + interval '11 seconds' and now() + interval '13 seconds',
  'a live call gets twelve seconds');

-- Sequential invocations model competing callers after the first commit: the
-- new future deadline makes every losing tick harmless.
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'call', 'a second participant tick cannot take a second transition');

select tests.act_as_admin();
select ok((select points is null from public.higher_or_lower_cards
  where match_id = (select v from tests.fx where k = 'm') and ordinal = 1),
  'the challenger remains unreadable throughout its call');
update public.higher_or_lower_matches set phase_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select user_id from public.higher_or_lower_players where match_id = (select v from tests.fx where k = 'm') order by seat desc limit 1));
select higher_or_lower.tick((select v from tests.fx where k = 'm'));
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'reveal', 'an expired call enters its reveal');
select ok((select points is not null and revealed_at is not null from public.higher_or_lower_cards
  where match_id = (select v from tests.fx where k = 'm') and ordinal = 1),
  'and only its reveal copies the points into the client-readable card');
select ok((select phase_deadline from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm'))
  between now() + interval '3 seconds' and now() + interval '5 seconds',
  'the reveal is held for four seconds');

-- The no-input machine plays all twelve questions, and then the whole of
-- sudden death, to a completed platform match. Nobody ever calls, so both
-- players tie at a best streak of zero — sudden death (#28) is entered and
-- then, with nobody ever right, no round can eliminate anyone, so it runs out
-- every spare before falling back to a shared placement. Deliberate deadline
-- jumps exercise the server transition, not a UI.
select tests.act_as_admin();
do $$
declare v_id uuid := (select v from tests.fx where k = 'm'); v_i int;
begin
  for v_i in 1..33 loop
    update public.higher_or_lower_matches set phase_deadline = now() - interval '1 second' where match_id = v_id;
    perform higher_or_lower_private.expire(v_id);
  end loop;
end $$;
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 'm')),
  'complete', 'the final reveal completes the board');
select is((select status from public.matches where id = (select v from tests.fx where k = 'm')),
  'complete', 'and completes the platform match');
select is((select count(*)::int from public.higher_or_lower_cards where match_id = (select v from tests.fx where k = 'm') and points is not null and ordinal <= 12),
  13, 'the played anchor and twelve challengers are all revealed at completion');

-- The sweep is a fallback. A live call receives a generous minute of grace;
-- intro and reveal, where no person has a decision in flight, are rescued fast.
insert into tests.fx (k, v) values ('s', tests.mkmatch(2, 'higher_or_lower'));
select tests.act_as((select user_id from public.run_participants where run_id = (
  select run_id from public.matches where id = (select v from tests.fx where k = 's')
) order by seat limit 1));
select higher_or_lower.start((select v from tests.fx where k = 's'));
select tests.act_as_admin();
update public.higher_or_lower_matches set phase_deadline = now() - interval '5 seconds'
 where match_id = (select v from tests.fx where k = 's');
select higher_or_lower_private.sweep();
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 's')),
  'call', 'a stalled intro is rescued within seconds');
update public.higher_or_lower_matches set phase_deadline = now() - interval '10 seconds'
 where match_id = (select v from tests.fx where k = 's');
select higher_or_lower_private.sweep();
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 's')),
  'call', 'a live call keeps its generous grace');
update public.higher_or_lower_matches set phase_deadline = now() - interval '2 minutes'
 where match_id = (select v from tests.fx where k = 's');
select higher_or_lower_private.sweep();
select is((select phase from public.higher_or_lower_matches where match_id = (select v from tests.fx where k = 's')),
  'reveal', 'an abandoned call is eventually advanced by the sweep');

select * from finish();
rollback;
