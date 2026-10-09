-- Wavelength's guess/reveal loop: score only the locked position, reveal only
-- then, and hand the next designated guesser the table.

begin;
select plan(25);

\ir support/harness.psql

create function tests.wl_deal_playing(p_n int, p_mode text, p_preset text, p_seed double precision, out match_id uuid)
returns uuid language plpgsql as $$
begin
  match_id := tests.mkmatch(p_n, 'wavelength_2v2');
  perform tests.act_as_admin();
  perform wavelength_private.deal_board(match_id, p_mode, p_preset, p_seed);
  update public.matches set status = 'playing', started_at = now() where id = match_id;
end $$;

create function tests.wl_open(p_match uuid) returns void language plpgsql as $$
begin
  update public.wavelength_matches set phase = 'guess', phase_deadline = now() + interval '30 seconds'
   where match_id = p_match;
  update public.wavelength_rounds set status = 'open'
   where match_id = p_match and round = 1;
end $$;

insert into tests.fx (k, v) values ('v', tests.wl_deal_playing(4, 'versus', null, 0.25));
select tests.wl_open((select v from tests.fx where k = 'v'));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'g1', guesser_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'v') and round = 1;
insert into tests.fx (k, v)
select 'p1', psychic_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'v') and round = 1;
insert into tests.fx (k, v)
select 'g2', guesser_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'v') and round = 2;
insert into tests.fx (k, v) values ('outsider', tests.mkuser('wl outsider'));

-- Put the target at a known centre, then probe all three edge pairs on fresh
-- rounds.  The target is only ever read here as test admin.
update public.wavelength_targets set target = 500 where match_id = (select v from tests.fx where k = 'v');
insert into public.wavelength_clues (match_id, round, clue)
values ((select v from tests.fx where k = 'v'), 1, 'a table-visible clue');

select tests.act_as((select v from tests.fx where k = 'g1'));
select throws_ok(format($$ select wavelength.lock_guess(%L, 1, -1) $$, (select v from tests.fx where k = 'v')),
  'P0001', 'position_out_of_range', 'a negative position is rejected');
select throws_ok(format($$ select wavelength.lock_guess(%L, 1, 1001) $$, (select v from tests.fx where k = 'v')),
  'P0001', 'position_out_of_range', 'a position beyond the dial is rejected');
select is((select count(*)::int from public.wavelength_targets where match_id = (select v from tests.fx where k = 'v') and round = 1), 0,
  'the guesser cannot read the target before the reveal');
select is((select revealed_target is null from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 1), true,
  'the public round has no target before lock');
select is((select count(*)::int from public.wavelength_cards where match_id = (select v from tests.fx where k = 'v') and round = 1), 1,
  'opening the round exposes its card to the table');
select is((select clue from public.wavelength_clues where match_id = (select v from tests.fx where k = 'v') and round = 1), 'a table-visible clue',
  'opening the round exposes its clue to the table');

select wavelength.lock_guess((select v from tests.fx where k = 'v'), 1, 480);
select tests.act_as_admin();
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 1), 4,
  'the bullseye boundary scores four');
select is((select revealed_target::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 1), 500,
  'locking copies the target to the public round');
select is((select current_round::int from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')), 2,
  'locking opens the next sequential round');
select is((select status from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 2), 'open',
  'the next round is open');
select tests.act_as((select v from tests.fx where k = 'g1'));
select is((select (wavelength.state((select v from tests.fx where k = 'v'))).team_scores), array[4::smallint, 0::smallint],
  'state carries running totals per team');

select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(format($$ select wavelength.lock_guess(%L, 2, 500) $$, (select v from tests.fx where k = 'v')),
  '42501', 'not_guesser', 'only the current round guesser can lock');
select tests.act_as((select v from tests.fx where k = 'g1'));
select throws_ok(format($$ select wavelength.lock_guess(%L, 1, 500) $$, (select v from tests.fx where k = 'v')),
  'P0001', 'guess_not_open', 'a locked round cannot be guessed twice');
select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(format($$ select wavelength.lock_guess(%L, 2, 500) $$, (select v from tests.fx where k = 'v')),
  '42501', 'not_a_participant', 'an outsider cannot lock a guess');

-- Directly reset each open round as admin and score exact edge neighbours.
select tests.act_as_admin();
update public.wavelength_matches set current_round = 3, phase = 'guess' where match_id = (select v from tests.fx where k = 'v');
update public.wavelength_rounds set status = 'open' where match_id = (select v from tests.fx where k = 'v') and round = 3;
insert into tests.fx (k, v) select 'g3', guesser_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 3;
select tests.act_as((select v from tests.fx where k = 'g3'));
select wavelength.lock_guess((select v from tests.fx where k = 'v'), 3, 479);
select tests.act_as_admin();
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 3), 3, 'just outside bullseye scores three');
update public.wavelength_matches set current_round = 4, phase = 'guess' where match_id = (select v from tests.fx where k = 'v');
update public.wavelength_rounds set status = 'open' where match_id = (select v from tests.fx where k = 'v') and round = 4;
insert into tests.fx (k, v) select 'g4', guesser_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 4;
select tests.act_as((select v from tests.fx where k = 'g4'));
select wavelength.lock_guess((select v from tests.fx where k = 'v'), 4, 440);
select tests.act_as_admin();
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 4), 3, 'adjacent-wedge edge scores three');
update public.wavelength_matches set current_round = 5, phase = 'guess' where match_id = (select v from tests.fx where k = 'v');
update public.wavelength_rounds set status = 'open' where match_id = (select v from tests.fx where k = 'v') and round = 5;
insert into tests.fx (k, v) select 'g5', guesser_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 5;
select tests.act_as((select v from tests.fx where k = 'g5'));
select wavelength.lock_guess((select v from tests.fx where k = 'v'), 5, 439);
select tests.act_as_admin();
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 5), 2, 'just outside an adjacent wedge scores two');
update public.wavelength_matches set current_round = 6, phase = 'guess' where match_id = (select v from tests.fx where k = 'v');
update public.wavelength_rounds set status = 'open' where match_id = (select v from tests.fx where k = 'v') and round = 6;
insert into tests.fx (k, v) select 'g6', guesser_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 6;
select tests.act_as((select v from tests.fx where k = 'g6'));
select wavelength.lock_guess((select v from tests.fx where k = 'v'), 6, 400);
select tests.act_as_admin();
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 6), 2, 'outer-wedge edge scores two');
update public.wavelength_matches set current_round = 7, phase = 'guess' where match_id = (select v from tests.fx where k = 'v');
update public.wavelength_rounds set status = 'open' where match_id = (select v from tests.fx where k = 'v') and round = 7;
insert into tests.fx (k, v) select 'g7', guesser_id from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 7;
select tests.act_as((select v from tests.fx where k = 'g7'));
select wavelength.lock_guess((select v from tests.fx where k = 'v'), 7, 399);
select tests.act_as_admin();
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'v') and round = 7), 0, 'outside the scoring zone scores zero');
select is((select phase_deadline is not null from public.wavelength_matches where match_id = (select v from tests.fx where k = 'v')), true,
  'each newly opened guess has a deadline');
select ok(has_function_privilege('authenticated', 'wavelength.lock_guess(uuid,integer,integer)', 'execute'),
  'authenticated players may lock guesses');
select ok(not has_function_privilege('anon', 'wavelength.lock_guess(uuid,integer,integer)', 'execute'),
  'anonymous callers may not lock guesses');

-- The positions above covered the right-hand edge of each band.  A short
-- co-op match covers the immediately-inside positions, completing at / either
-- side of all three score boundaries.
insert into tests.fx (k, v) values ('c', tests.wl_deal_playing(2, 'coop', 'short', 0.5));
select tests.wl_open((select v from tests.fx where k = 'c'));
select tests.act_as_admin();
update public.wavelength_targets set target = 500 where match_id = (select v from tests.fx where k = 'c');
insert into tests.fx (k, v)
select 'cg' || round::text, guesser_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'c') and round <= 3;
select tests.act_as((select v from tests.fx where k = 'cg1'));
select wavelength.lock_guess((select v from tests.fx where k = 'c'), 1, 481);
select tests.act_as((select v from tests.fx where k = 'cg2'));
select wavelength.lock_guess((select v from tests.fx where k = 'c'), 2, 441);
select tests.act_as((select v from tests.fx where k = 'cg3'));
select wavelength.lock_guess((select v from tests.fx where k = 'c'), 3, 401);
select tests.act_as_admin();
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'c') and round = 1), 4,
  'inside the bullseye edge still scores four');
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'c') and round = 2), 3,
  'inside the adjacent-wedge edge still scores three');
select is((select points::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'c') and round = 3), 2,
  'inside the outer-wedge edge still scores two');

select * from finish();
rollback;
