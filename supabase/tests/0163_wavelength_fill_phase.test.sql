-- Wavelength's fill phase: psychics privately write all their clues, while
-- everyone else gets only the status row.  The final clue atomically opens
-- the first guessing round (issue #99).

begin;
select plan(22);

\ir support/harness.psql

create function tests.wl_member(p_match uuid, p_i int) returns uuid
language sql stable security definer as $$
  select rp.user_id
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match
   order by rp.seat
  offset p_i - 1 limit 1;
$$;

create function tests.wl_deal(p_n int, p_mode text, p_preset text, p_seed double precision, out match_id uuid)
returns uuid language plpgsql as $$
begin
  match_id := tests.mkmatch(p_n, 'wavelength_2v2');
  perform tests.act_as_admin();
  perform wavelength_private.deal_board(match_id, p_mode, p_preset, p_seed);
  update public.matches set status = 'playing', started_at = now() where id = match_id;
end $$;

insert into tests.fx (k, v) values ('m', tests.wl_deal(4, 'versus', null, 0.25));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'p1', psychic_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'm') and round = 1;
insert into tests.fx (k, v)
select 'g1', guesser_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'm') and round = 1;
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));

-- ----------------------------------------------------------- validation ----

select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(format($$ select wavelength.submit_clue(%L, 1, '') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'clue_required', 'a clue needs at least one word');
select throws_ok(format($$ select wavelength.submit_clue(%L, 1, 'QB1') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'clue_contains_digit', 'a clue containing a digit is rejected');
select throws_ok(format($$ select wavelength.submit_clue(%L, 1, 'one two three four five six seven eight nine') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'clue_too_many_words', 'a clue with more than eight words is rejected');
select throws_ok(format($$ select wavelength.submit_clue(%L, 1, %L) $$,
  (select v from tests.fx where k = 'm'), repeat('a', 101)),
  'P0001', 'clue_too_long', 'a clue longer than 100 characters is rejected');
select lives_ok(format($$ select wavelength.submit_clue(%L, 1, 'good clue') $$, (select v from tests.fx where k = 'm')),
  'a psychic can write their own round');
select lives_ok(format($$ select wavelength.submit_clue(%L, 1, 'better clue') $$, (select v from tests.fx where k = 'm')),
  'a psychic may replace their clue during fill');
select is((select clue from public.wavelength_clues where match_id = (select v from tests.fx where k = 'm') and round = 1),
  'better clue', 'replacement stores the latest clue');

select tests.act_as((select v from tests.fx where k = 'g1'));
select throws_ok(format($$ select wavelength.submit_clue(%L, 1, 'not mine') $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_psychic', 'a non-psychic cannot submit for that round');
select throws_ok(format($$ select wavelength.submit_clue(%L, 99, 'not mine') $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_psychic', 'a participant cannot submit a nonexistent round');
select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(format($$ select wavelength.submit_clue(%L, 1, 'outside') $$, (select v from tests.fx where k = 'm')),
  '42501', 'not_a_participant', 'an outsider cannot submit a clue');

-- ------------------------------------------------------------- secrecy ----

select tests.act_as((select v from tests.fx where k = 'p1'));
select is((select count(*)::int from public.wavelength_clues where match_id = (select v from tests.fx where k = 'm') and round = 1), 1,
  'the psychic can reread their clue');
select tests.act_as((select v from tests.fx where k = 'g1'));
select is((select count(*)::int from public.wavelength_clues where match_id = (select v from tests.fx where k = 'm') and round = 1), 0,
  'the guesser cannot read the clue during fill');
select is((select count(*)::int from public.wavelength_clue_statuses where match_id = (select v from tests.fx where k = 'm') and round = 1), 1,
  'the guesser sees that the clue was written');
select is((select count(*)::int from public.wavelength_cards where match_id = (select v from tests.fx where k = 'm') and round = 1), 0,
  'the fill phase still withholds cards from non-psychics');
select is((select count(*)::int from public.wavelength_targets where match_id = (select v from tests.fx where k = 'm') and round = 1), 0,
  'the fill phase still withholds targets from non-psychics');

-- ------------------------------------------------------------ completion ---

select tests.act_as_admin();
insert into tests.fx (k, v)
select 'p' || r.round::text, r.psychic_id
  from public.wavelength_rounds r
 where r.match_id = (select v from tests.fx where k = 'm') and r.round > 1;
select tests.act_as((select v from tests.fx where k = 'p2'));
select wavelength.submit_clue((select v from tests.fx where k = 'm'), 2, 'round two');
select tests.act_as((select v from tests.fx where k = 'p3'));
select wavelength.submit_clue((select v from tests.fx where k = 'm'), 3, 'round three');
select tests.act_as((select v from tests.fx where k = 'p4'));
select wavelength.submit_clue((select v from tests.fx where k = 'm'), 4, 'round four');
select tests.act_as((select v from tests.fx where k = 'p5'));
select wavelength.submit_clue((select v from tests.fx where k = 'm'), 5, 'round five');
select tests.act_as((select v from tests.fx where k = 'p6'));
select wavelength.submit_clue((select v from tests.fx where k = 'm'), 6, 'round six');
select tests.act_as((select v from tests.fx where k = 'p7'));
select wavelength.submit_clue((select v from tests.fx where k = 'm'), 7, 'round seven');
select tests.act_as((select v from tests.fx where k = 'p8'));
select lives_ok(format($$ select wavelength.submit_clue(%L, 8, 'round eight') $$, (select v from tests.fx where k = 'm')),
  'the final expected clue is accepted');
select tests.act_as_admin();
select is((select phase from public.wavelength_matches where match_id = (select v from tests.fx where k = 'm')),
  'guess', 'the final clue opens guessing immediately');
select is((select status from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'm') and round = 1),
  'open', 'the first round opens for guessing');
select is((select count(*)::int from public.wavelength_clue_statuses where match_id = (select v from tests.fx where k = 'm')),
  8, 'each completed clue has exactly one public status row');
select tests.act_as((select v from tests.fx where k = 'p1'));
select throws_ok(format($$ select wavelength.submit_clue(%L, 1, 'too late') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'clue_not_open', 'a clue cannot be submitted outside fill');

-- ------------------------------------------------------------- privilege ---

select tests.act_as_admin();
select ok(has_function_privilege('authenticated', 'wavelength.submit_clue(uuid,integer,text)', 'execute'),
  'authenticated players may call submit_clue');
select ok(not has_function_privilege('anon', 'wavelength.submit_clue(uuid,integer,text)', 'execute'),
  'anonymous requests may not call submit_clue');

select * from finish();
rollback;
