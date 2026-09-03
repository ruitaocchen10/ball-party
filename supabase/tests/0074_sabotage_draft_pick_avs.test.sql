-- Tests for sabotage_draft.pick_avs (migration 0074): each pick's
-- Approximate Value, gated by the exact same visibility 0073 already gives
-- sabotage_draft_picks itself — own picks always, a teammate's once that
-- seat's own turn has resolved, nothing for anyone not seated at the table.

begin;
select plan(4);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));

select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- Three expired turns close out round 1 on timeout (the same fast path
-- 0069's own suite uses) — every seat gets a real, random round-1 pick,
-- with no need for a test double acting as each player just to submit one.
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select is(
  (select current_round::int from public.sabotage_draft_matches
    where match_id = (select v from tests.fx where k = 'm')),
  2,
  'three expired turns close out round 1, so every seat''s round-1 pick has resolved'
);

-- The AV a correct answer has to match, read directly off the pool the
-- engine itself draws from — computed as admin, since neither p0 nor p1
-- holds (or should hold) any grant on private.av_roster_players.
insert into tests.num (k, v)
select 'expected_av', pool.av
  from public.sabotage_draft_picks p
  join public.sabotage_draft_rounds r
    on r.match_id = p.match_id and r.round_number = p.round_number
  join public.sabotage_draft_round_spins spin
    on spin.match_id = p.match_id and spin.round_number = p.round_number and spin.user_id = p.user_id
  join private.av_roster_players pool
    on pool.franchise_code = spin.franchise_code
   and pool.player_id = p.player_id and pool.season = p.season
   and pool.slot_category = any(sabotage_draft_private.pool_categories(r.slot))
 where p.match_id = (select v from tests.fx where k = 'm')
   and p.round_number = 1
   and p.user_id = (select v from tests.fx where k = 'p0');

select tests.act_as((select v from tests.fx where k = 'p0'));
select is(
  (select av::int from sabotage_draft.pick_avs((select v from tests.fx where k = 'm'))
    where round_number = 1 and user_id = (select v from tests.fx where k = 'p0')),
  (select v from tests.num where k = 'expected_av'),
  'a player reads the correct AV for their own resolved pick'
);

select tests.act_as((select v from tests.fx where k = 'p1'));
select is(
  (select av::int from sabotage_draft.pick_avs((select v from tests.fx where k = 'm'))
    where round_number = 1 and user_id = (select v from tests.fx where k = 'p0')),
  (select v from tests.num where k = 'expected_av'),
  'a teammate reads the same AV for that pick, once its own turn has resolved (mirrors 0073)'
);

select tests.act_as((select v from tests.fx where k = 'outsider'));
select throws_ok(
  format($$ select * from sabotage_draft.pick_avs(%L) $$,
         (select v from tests.fx where k = 'm')),
  '42501', 'not_a_participant',
  'someone not seated at the table cannot read any of it'
);

select * from finish();
rollback;
