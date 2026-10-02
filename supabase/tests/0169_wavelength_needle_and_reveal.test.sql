-- The server remembers the guesser's reported needle, auto-locks there, and
-- records where each guess landed for the public reveal.

begin;
select plan(8);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.mkmatch(2, 'wavelength_2v2'));
select tests.act_as_admin();
select wavelength_private.deal_board((select v from tests.fx where k = 'm'), 'coop', 'short', 0.25);
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm');
insert into tests.fx (k, v) select 'guesser', guesser_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1;
insert into tests.fx (k, v) select 'psychic', psychic_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1;

-- Open round 1 for guessing with a pinned target.
update public.wavelength_matches set phase = 'guess', phase_deadline = now() + interval '60 seconds', phase_started_at = now() where match_id = (select v from tests.fx where k = 'm');
update public.wavelength_rounds set status = 'open' where match_id = (select v from tests.fx where k = 'm') and round = 1;
update public.wavelength_targets set target = 300 where match_id = (select v from tests.fx where k = 'm') and round = 1;

select tests.act_as((select v from tests.fx where k = 'psychic'));
select throws_ok(format($$ select wavelength.report_needle(%L, 1, 300) $$, (select v from tests.fx where k = 'm')), '42501', 'not_guesser', 'only the guesser may report the needle');

select tests.act_as((select v from tests.fx where k = 'guesser'));
select throws_ok(format($$ select wavelength.report_needle(%L, 1, 1001) $$, (select v from tests.fx where k = 'm')), 'P0001', 'position_out_of_range', 'a needle off the scale is rejected');
select throws_ok(format($$ select wavelength.report_needle(%L, 2, 300) $$, (select v from tests.fx where k = 'm')), '42501', 'not_guesser', 'only the open round accepts a needle');
select lives_ok(format($$ select wavelength.report_needle(%L, 1, 300) $$, (select v from tests.fx where k = 'm')), 'the guesser reports their needle');
select lives_ok(format($$ select wavelength.report_needle(%L, 1, 310) $$, (select v from tests.fx where k = 'm')), 'a later report replaces the earlier one');

select throws_ok(format($$ select * from wavelength_private.needles $$), '42501', null, 'clients cannot read reported needles');

-- Expiry locks at the reported needle (310 is within the bullseye wedge of 300).
select tests.act_as_admin();
update public.wavelength_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'm');
select tests.act_as((select v from tests.fx where k = 'guesser'));
select wavelength.tick((select v from tests.fx where k = 'm'));
select tests.act_as_admin();
select is((select guess_position::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1), 310, 'auto-lock uses the reported needle');
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1), 4, 'and scores it as a bullseye');

select * from finish();
rollback;
