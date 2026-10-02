-- Sabotage draft game modes: full (14 rounds), standard (10), quick (7).
-- Round count and slot order come from the mode, X_FACTOR stays last, FLEX
-- and DEF draw from their position pools, and the season is graded against
-- the mode's own baseline.
begin;
select plan(27);

\ir support/harness.psql

-- ------------------------------------------------------------ mode tables --

select is(sabotage_draft_private.mode_slots('quick'),
  array['QB', 'RB1', 'WR1', 'TE', 'FLEX', 'DEF', 'X_FACTOR'], 'quick mode slot order');
select is(sabotage_draft_private.mode_slots('standard'),
  array['QB', 'RB1', 'RB2', 'WR1', 'WR2', 'TE', 'FLEX', 'DEF', 'ST', 'X_FACTOR'], 'standard mode slot order');
select is(array_length(sabotage_draft_private.mode_slots('full'), 1), 14, 'full mode is still fourteen rounds');
select is(sabotage_draft_private.mode_slots('nonsense'), null, 'an unknown mode has no slots');

select is(sabotage_draft_private.pool_categories('FLEX'), array['RB', 'WR', 'TE'], 'FLEX draws from RB, WR and TE');
select is(sabotage_draft_private.pool_categories('DEF'), array['DL', 'LB', 'CB', 'S'], 'DEF draws from DL, LB, CB and S');

select is(sabotage_draft_private.baseline_roster_strength('full'), 93, 'full baseline is the original 93');
select is(sabotage_draft_private.baseline_roster_strength('standard'), 62, 'standard baseline');
select is(sabotage_draft_private.baseline_roster_strength('quick'), 52, 'quick baseline');
select is(sabotage_draft_private.strength_scale('full'), 25::double precision, 'full keeps the original 25-point scale');
select ok(sabotage_draft_private.strength_scale('quick') < sabotage_draft_private.strength_scale('standard'),
  'smaller rosters get a tighter scale');
select is(sabotage_draft_private.win_probability(52, 52, sabotage_draft_private.strength_scale('quick')),
  0.5::double precision, 'a roster at its own mode''s baseline wins half its games');

-- ------------------------------------------------------------------- deal --

insert into tests.fx (k, v) values ('q', tests.mkmatch(2, 'sabotage_draft'));
insert into tests.fx (k, v) values ('s', tests.mkmatch(2, 'sabotage_draft'));
select tests.act_as_admin();
select sabotage_draft_private.deal_board((select v from tests.fx where k = 'q'), 0.4, 'quick');
select sabotage_draft_private.deal_board((select v from tests.fx where k = 's'), 0.4, 'standard');

select is((select round_count::int from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'q')),
  7, 'a quick match has seven rounds');
select is((select mode from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'q')),
  'quick', 'and records its mode');
select is((select array_agg(slot order by round_number) from public.sabotage_draft_rounds where match_id = (select v from tests.fx where k = 'q')),
  array['QB', 'RB1', 'WR1', 'TE', 'FLEX', 'DEF', 'X_FACTOR'], 'quick rounds deal in slot order');
select is((select round_count::int from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 's')),
  10, 'a standard match has ten rounds');
select is((select count(*)::int from public.sabotage_draft_round_spins where match_id = (select v from tests.fx where k = 's')),
  20, 'every seat gets one spin per standard round');
select is((select count(*)::int from public.sabotage_draft_round_spins sp
   join public.sabotage_draft_rounds r on r.match_id = sp.match_id and r.round_number = sp.round_number
  where sp.match_id = (select v from tests.fx where k = 's') and r.slot = 'DEF'
    and not exists (select 1 from private.av_roster_players p where p.franchise_code = sp.franchise_code
                      and p.slot_category in ('DL', 'LB', 'CB', 'S'))),
  0, 'a DEF round never spins a franchise with no defensive player');
select throws_ok(format($$ select sabotage_draft_private.deal_board(%L, 0.1, 'nonsense') $$,
  (select v from tests.fx where k = 'q')), '22023', 'invalid_mode', 'an unknown mode is refused');

-- ------------------------------------------------------- a whole quick match --

select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'q');
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'q') order by seat;

-- Six ordinary rounds, two seats each.
do $$
declare i int; v_match uuid := (select v::uuid from tests.fx where k = 'q');
begin
  for i in 1 .. 12 loop perform tests.sd_expire_turn(v_match); end loop;
end $$;
select is((select current_round::int from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'q')),
  7, 'the sixth round hands off to the X-Factor as round seven');

select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(format($$ select sabotage_draft.submit_pick(%L, c.player_id, c.season)
  from tests.sd_pick_candidate(%L, 7::smallint, %L, 'RB') c $$,
  (select v from tests.fx where k = 'q'), (select v from tests.fx where k = 'q'), (select v from tests.fx where k = 'p0')),
  'the X-Factor accepts an RB');
select tests.act_as_admin();
select tests.sd_expire_turn((select v from tests.fx where k = 'q'));
select tests.act_as((select v from tests.fx where k = 'p0'));
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'WR3') $$,
  (select v from tests.fx where k = 'q')), 'P0001', 'invalid_x_factor_slot',
  'a slot that quick mode does not have is not a valid replacement target');
select throws_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'OL') $$,
  (select v from tests.fx where k = 'q')), 'P0001', 'invalid_x_factor_slot', 'nor is a non-skill slot');
select is((select replace_slot from sabotage_draft.submit_x_factor_decision((select v from tests.fx where k = 'q'), 'FLEX')),
  'FLEX', 'an RB X-Factor can replace the FLEX slot');

select tests.act_as_admin();
select tests.sd_expire_turn((select v from tests.fx where k = 'q'));
select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, null) $$,
  (select v from tests.fx where k = 'q')), 'the last seat discards, finishing the match');

select tests.act_as_admin();
select is((select count(*)::int from public.sabotage_draft_standings where match_id = (select v from tests.fx where k = 'q')),
  2, 'a quick match still plays out its season');
select ok((select min(roster_strength) > 0 from public.sabotage_draft_standings where match_id = (select v from tests.fx where k = 'q')),
  'and scores every roster from the six non-X-Factor cards');

select * from finish();
rollback;
