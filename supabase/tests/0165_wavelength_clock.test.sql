-- Pinned-deadline coverage for Wavelength's expiry and presence contract.

begin;
select plan(20);

\ir support/harness.psql

create function tests.wl_clock_deal(out match_id uuid) returns uuid language plpgsql as $$
begin
  match_id := tests.mkmatch(2, 'wavelength_2v2');
  perform tests.act_as_admin();
  perform wavelength_private.deal_board(match_id, 'coop', 'short', 0.25);
  update public.matches set status = 'playing', started_at = now() where id = match_id;
end $$;

insert into tests.fx (k, v) values ('m', tests.wl_clock_deal());
select tests.act_as_admin();
insert into tests.fx (k, v) select 'p1', user_id from public.wavelength_players where match_id = (select v from tests.fx where k = 'm') order by seat limit 1;
insert into tests.fx (k, v) select 'p2', user_id from public.wavelength_players where match_id = (select v from tests.fx where k = 'm') order by seat offset 1 limit 1;
insert into tests.fx (k, v) values ('outsider', tests.mkuser('wavelength clock outsider'));

-- An early (and repeated) tick is only a heartbeat.
select tests.act_as((select v from tests.fx where k = 'p1'));
select is((wavelength.tick((select v from tests.fx where k = 'm'))).phase, 'fill', 'an early tick does not advance fill');
select is((wavelength.tick((select v from tests.fx where k = 'm'))).phase, 'fill', 'a repeated early tick is harmless');
select tests.act_as_admin();
select ok((select last_seen_at > now() - interval '5 seconds' and not absent from public.wavelength_players where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'p1')), 'tick stamps its caller present');

select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(format($$ select wavelength.tick(%L) $$, (select v from tests.fx where k = 'm')), '42501', 'not_a_participant', 'a non-participant cannot tick');
select tests.act_as_admin();
update public.matches set status = 'paused' where id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(format($$ select wavelength.tick(%L) $$, (select v from tests.fx where k = 'm')), 'P0001', 'match_not_playing', 'a paused match rejects tick');
select tests.act_as_admin();
update public.matches set status = 'playing' where id = (select v from tests.fx where k = 'm');

-- A fill expiry skips each missing clue, reveals it normally, and advances to
-- the first written round rather than ending a co-op match for an absent seat.
insert into public.wavelength_clues (match_id, round, clue) values ((select v from tests.fx where k = 'm'), 2, 'written in time');
insert into public.wavelength_clue_statuses (match_id, round) values ((select v from tests.fx where k = 'm'), 2);
update public.wavelength_players set last_seen_at = now() - interval '2 minutes' where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'p2');
update public.wavelength_matches set phase_deadline = now() - interval '1 second', phase_started_at = now() - interval '1 minute' where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'p1'));
select is((wavelength.tick((select v from tests.fx where k = 'm'))).phase, 'guess', 'expired fill advances to guessing');
select tests.act_as_admin();
select is((select status from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1), 'skipped', 'an unwritten clue skips its round');
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1), 0, 'a skipped round scores zero');
select ok((select revealed_target is not null from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1), 'a skipped round has a normal public reveal');
select is((select current_round::int from public.wavelength_matches where match_id = (select v from tests.fx where k = 'm')), 2, 'the first written round opens next');
select ok((select absent from public.wavelength_players where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'p2')), 'a silent player is latched absent at reveal');

-- The first heartbeat after returning clears that latched state even though
-- the co-op table carries on without them.
select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(format($$ select wavelength.tick(%L) $$, (select v from tests.fx where k = 'm')), 'an absent player can rejoin by ticking');
select tests.act_as_admin();
select ok((select not absent from public.wavelength_players where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'p2')), 'the returning tick clears absence');

-- Pin a target and expire the open guess.  With no server-side position yet,
-- expiry locks the documented neutral/default position (500).
update public.wavelength_targets set target = 500 where match_id = (select v from tests.fx where k = 'm') and round = 2;
update public.wavelength_matches set phase_deadline = now() - interval '1 second', phase_started_at = now() - interval '1 minute' where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'p1'));
select is((wavelength.tick((select v from tests.fx where k = 'm'))).phase, 'complete', 'expired guess records the completed match when every remaining round was skipped');
select tests.act_as_admin();
select is((select status from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 2), 'locked', 'expired guess auto-locks');
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 2), 4, 'auto-lock scores through the ordinary lock path');
select ok((select revealed_target is not null from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 2), 'auto-lock produces a normal public reveal');
select is((select count(*)::int from public.wavelength_players where match_id = (select v from tests.fx where k = 'm')), 2, 'absence never removes a co-op seat');
select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(format($$ select wavelength.tick(%L) $$, (select v from tests.fx where k = 'm')), 'P0001', 'match_not_playing', 'a completed match rejects further ticks');
select ok(has_function_privilege('authenticated', 'wavelength.tick(uuid)', 'EXECUTE'), 'authenticated players may tick');

select * from finish();
rollback;
