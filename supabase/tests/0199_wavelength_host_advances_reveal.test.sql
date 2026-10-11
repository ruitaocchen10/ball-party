-- A locked guess holds the table on its card; only the host moves on.

begin;
select plan(12);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.mkmatch(2, 'wavelength_2v2'));
select tests.act_as_admin();
select wavelength_private.deal_board((select v from tests.fx where k = 'm'), 'coop', 'short', 0.25);
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm');
insert into tests.fx (k, v) select 'guesser', guesser_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1;
insert into tests.fx (k, v) select 'p2', id from auth.users where id <> (select host_id from public.lobbies order by created_at desc limit 1) and id in (select user_id from public.wavelength_players where match_id = (select v from tests.fx where k = 'm'));
insert into tests.fx (k, v) select 'host', host_id from public.lobbies where id = (select lobby_id from public.runs where id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm')));

update public.wavelength_matches set phase = 'guess', phase_deadline = now() + interval '60 seconds', phase_started_at = now() where match_id = (select v from tests.fx where k = 'm');
update public.wavelength_rounds set status = 'open' where match_id = (select v from tests.fx where k = 'm') and round = 1;
update public.wavelength_targets set target = 500 where match_id = (select v from tests.fx where k = 'm') and round = 1;

select tests.act_as((select v from tests.fx where k = 'host'));
select throws_ok(format($$ select wavelength.next_card(%L) $$, (select v from tests.fx where k = 'm')), 'P0001', 'reveal_not_open', 'there is nothing to advance while a guess is open');

select tests.act_as((select v from tests.fx where k = 'guesser'));
select wavelength.lock_guess((select v from tests.fx where k = 'm'), 1, 500);
select tests.act_as_admin();
select is((select phase from public.wavelength_matches where match_id = (select v from tests.fx where k = 'm')), 'reveal', 'a lock parks the table on the reveal');
select is((select current_round::int from public.wavelength_matches where match_id = (select v from tests.fx where k = 'm')), 1, 'the table stays on the locked card');
select is((select phase_deadline is null from public.wavelength_matches where match_id = (select v from tests.fx where k = 'm')), true, 'the reveal has no clock');

-- Ticking cannot move the table on.
select tests.act_as((select v from tests.fx where k = 'guesser'));
select is((wavelength.tick((select v from tests.fx where k = 'm'))).phase, 'reveal', 'a tick leaves the reveal alone');

-- Only the host advances.
select tests.act_as((select v from tests.fx where k = 'p2'));
select throws_ok(format($$ select wavelength.next_card(%L) $$, (select v from tests.fx where k = 'm')), '42501', 'not_host', 'a non-host cannot advance');
select ok(not has_function_privilege('anon', 'wavelength.next_card(uuid)', 'execute'), 'anonymous callers cannot advance');

select tests.act_as((select v from tests.fx where k = 'host'));
select is((wavelength.next_card((select v from tests.fx where k = 'm'))).phase, 'guess', 'the host opens the next card');
select tests.act_as_admin();
select is((select current_round::int from public.wavelength_matches where match_id = (select v from tests.fx where k = 'm')), 2, 'the next card is round 2');
select is((select status from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 2), 'open', 'and it is open for guessing');
select is((select phase_deadline > now() from public.wavelength_matches where match_id = (select v from tests.fx where k = 'm')), true, 'with a fresh guess clock');

select tests.act_as((select v from tests.fx where k = 'host'));
select throws_ok(format($$ select wavelength.next_card(%L) $$, (select v from tests.fx where k = 'm')), 'P0001', 'reveal_not_open', 'a second tap cannot skip a card');

select * from finish();
rollback;
