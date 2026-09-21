-- Tests for QB Season Builder's run loop, third slice: the respin (migration
-- 0122). See issue #74.
--
-- One respin per run. It rerolls the whole spin, it is final, and it can be
-- used at the start of any round. Played through the public calls as a real
-- player and as a guest, with RLS in force.

begin;
select plan(25);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('a', tests.mkuser('ava')),
       ('guest', tests.mkguest('gina')),
       ('stranger', tests.mkuser('sten'));

select tests.act_as_admin();
select tests.qsb_fixtures();

-- ------------------------------------------------------------ the reroll --

insert into tests.fx (k, v)
select 'm', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'm'), 1::smallint, 'phi', 2017::smallint);

select tests.act_as((select v from tests.fx where k = 'a'));
select lives_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'm')),
  'a respin can be used at the start of the first round'
);
select isnt(
  (select franchise_code || season from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  'phi2017',
  'it rerolls the whole spin: the team-season on offer is a different one'
);
select ok(
  (select franchise_code || season from qb_season_builder.state((select v from tests.fx where k = 'm')))
    in ('kan2018', 'kan2019', 'nwe2017'),
  'still one with a qualifying quarterback'
);
select is(
  (select respin_used from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  true,
  'and the run records that its respin is spent'
);
select is(
  (select current_round::int from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  1,
  'a respin does not consume the round'
);
select is(
  (select picks from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  '[]'::jsonb,
  'or fill a slot'
);

-- The new spin is the one stored, and it is the one every read returns.
select is(
  (select franchise_code || season from qb_season_builder.state((select v from tests.fx where k = 'm'))),
  (select franchise_code || season from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1 and attempt = 2),
  'the new spin is stored with the run and reads back the same'
);
select is(
  (select count(*)::int from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 2),
  0,
  'and round 2 is still not dealt'
);

-- The spin it replaced is kept, not erased: it was shown to the player.
select is(
  (select franchise_code || season from public.qb_season_builder_spins
    where match_id = (select v from tests.fx where k = 'm') and round_number = 1 and attempt = 1),
  'phi2017',
  'the spin that was rerolled away is kept, since the player saw it'
);

-- Final: the new spin is what is picked from.
select throws_ok(
  format($$ select qb_season_builder.pick(%L, 'accuracy', 'WentCa00') $$, (select v from tests.fx where k = 'm')),
  'P0001', 'source_not_on_spin',
  'the rerolled spin cannot be picked from any more'
);

select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'respin_used',
  'a second respin in the same round is refused'
);

-- ------------------------------------------------------- any round, once --

-- Take a pick from the respun spin, which opens round 2.
select qb_season_builder.pick((select v from tests.fx where k = 'm'), 'accuracy',
  (select options -> 'quarterbacks' -> 0 ->> 'player_id'
     from qb_season_builder.state((select v from tests.fx where k = 'm'))));
select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'm')),
  'P0001', 'respin_used',
  'nor in a later round: it is one per run, not one per round'
);

-- A fresh run for each round the respin is used in.
insert into tests.fx (k, v)
select 'r4', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.qsb_fill((select v from tests.fx where k = 'r4'), 3);
select tests.act_as_admin();
select tests.qsb_set_spin((select v from tests.fx where k = 'r4'), 4::smallint, 'phi', 2017::smallint);
select tests.act_as((select v from tests.fx where k = 'a'));
select lives_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'r4')),
  'a respin can be spent at the start of round 4'
);
select is(
  (select current_round::int from qb_season_builder.state((select v from tests.fx where k = 'r4'))),
  4,
  'on the same round, with its three earlier picks intact'
);
select is(
  (select jsonb_array_length(picks) from qb_season_builder.state((select v from tests.fx where k = 'r4'))),
  3,
  'three picks still stand'
);

insert into tests.fx (k, v)
select 'r6', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.qsb_fill((select v from tests.fx where k = 'r6'), 5);
select lives_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'r6')),
  'or at the start of the last round'
);

-- After the respin the round still ends the ordinary way, and the next round
-- is dealt fresh.
select is(
  (select current_round::int from qb_season_builder.pick(
      (select v from tests.fx where k = 'r4'), 'iq',
      (select options -> 'quarterbacks' -> 0 ->> 'player_id'
         from qb_season_builder.state((select v from tests.fx where k = 'r4'))))),
  5,
  'a pick from the respun spin closes the round like any other'
);

-- A run that has nothing left to spin.
insert into tests.fx (k, v)
select 'done', tests.qsb_start((select v from tests.fx where k = 'a'));
select tests.qsb_fill((select v from tests.fx where k = 'done'), 6);
select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'done')),
  'P0001', 'draft_complete',
  'a run with every slot filled has no spin to reroll'
);

-- ------------------------------------------------- it is a real reroll --

-- Forty runs, each pinned to one team-season and respun: not one lands where it
-- started, and each lands on a team-season that can be spun.
select tests.act_as_admin();
do $$
declare
  v_user  uuid := tests.mkuser('respinner');
  v_match uuid;
  v_same  int := 0;
  v_bad   int := 0;
  v_key   text;
begin
  for i in 1 .. 40 loop
    v_match := tests.qsb_start(v_user);
    perform tests.qsb_set_spin(v_match, 1::smallint, 'phi', 2017::smallint);
    perform qb_season_builder.respin(v_match);
    select franchise_code || season into v_key from qb_season_builder.state(v_match);
    if v_key = 'phi2017' then v_same := v_same + 1; end if;
    if v_key not in ('kan2018', 'kan2019', 'nwe2017', 'phi2017') then v_bad := v_bad + 1; end if;
  end loop;
  perform tests.act_as_admin();
  insert into tests.num (k, v) values ('respin_same', v_same), ('respin_bad', v_bad);
end $$;
select tests.act_as_admin();
select is((select v from tests.num where k = 'respin_same'), 0, 'a respin never hands back the spin it replaced');
select is((select v from tests.num where k = 'respin_bad'), 0, 'and always draws from team-seasons with a qualifying quarterback');

-- ------------------------------------------------------ guests and the rules --

insert into tests.fx (k, v)
select 'g', tests.qsb_start((select v from tests.fx where k = 'guest'), 'visible', true);
select lives_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'g')),
  'a guest can respin too'
);
select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'g')),
  'P0001', 'respin_used',
  'and only once'
);

select tests.act_as((select v from tests.fx where k = 'stranger'));
select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'g')),
  '42501', 'not_a_participant',
  'someone else cannot spend a run''s respin'
);
select tests.act_as((select v from tests.fx where k = 'a'));
select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select id from public.start_solo_run('qb_season_builder'))),
  'P0001', 'match_not_playing',
  'a run that has not been dealt has nothing to respin'
);
select tests.act_as_admin();
select throws_ok(
  format($$ select qb_season_builder.respin(%L) $$, (select v from tests.fx where k = 'g')),
  '42501', 'not_authenticated',
  'and without a session there is no one to respin'
);

select * from finish();
rollback;
