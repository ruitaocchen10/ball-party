-- A completed X-Factor phase atomically turns every final roster into a
-- deterministic season and resolves every record tie before the match ends.
begin;
select plan(11);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.41));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- Timeout cards are legitimate finished rosters, including for an absent
-- player.  This also exercises the shared ordinary resolution path all the
-- way through round fourteen — one turn (timed-out pick, unused guess
-- window) per seat, thirteen rounds, then the same per-seat turn once more
-- for round 14 before each seat's own X-Factor decision.
update public.sabotage_draft_players set absent = true
 where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'p2');
do $$
declare i int; v_match uuid := (select v::uuid from tests.fx where k = 'm');
begin
  for i in 1 .. 39 loop
    perform tests.sd_expire_turn(v_match);
  end loop;
end $$;

select tests.act_as_admin();
select tests.sd_expire_turn((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, %L) $$,
  (select v from tests.fx where k = 'm'),
  (select replace_slot from tests.sd_x_factor_replace_slot(
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p0')
  ))), 'an X-Factor replacement remains a valid final roster');
select tests.act_as_admin();
select tests.sd_expire_turn((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, null) $$,
  (select v from tests.fx where k = 'm')), 'an X-Factor discard remains a valid final roster');
select tests.act_as_admin();
select tests.sd_expire_turn((select v from tests.fx where k = 'm'));
select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, %L) $$,
  (select v from tests.fx where k = 'm'),
  (select replace_slot from tests.sd_x_factor_replace_slot(
    (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p2')
  ))), 'the last decision triggers the season simulation');

select tests.act_as_admin();
select is((select count(*)::int from public.sabotage_draft_standings where match_id = (select v from tests.fx where k = 'm')), 3,
  'every seated player, including the disconnected player, has a standing');
select is((select count(*)::int from public.sabotage_draft_standings where match_id = (select v from tests.fx where k = 'm') and wins + losses = 17), 3,
  'each standing came from seventeen simulated games');
select ok((select bool_and(roster_strength <> 0) from public.sabotage_draft_standings where match_id = (select v from tests.fx where k = 'm')),
  'strength is calculated from the settled roster cards');
select is((select count(*)::int from sabotage_draft_private.seasons where match_id = (select v from tests.fx where k = 'm')), 1,
  'the simulation stores its seed record exactly once');
select is((select seed from sabotage_draft_private.seasons where match_id = (select v from tests.fx where k = 'm')),
  (select seed from sabotage_draft_private.boards where match_id = (select v from tests.fx where k = 'm')),
  'the stored board seed is also the simulation seed');
select is((select status::text from public.matches where id = (select v from tests.fx where k = 'm')), 'complete',
  'season and any tiebreak bracket complete the match');
select is((select count(*)::int from public.match_players where match_id = (select v from tests.fx where k = 'm')), 3,
  'the resolved standings are handed to the platform placements');

-- A strictly better record must always outrank a strictly worse one. Before
-- the standings-rank fix, every player who wasn't part of a tied win group
-- was left at the literal tiebreak_rank the row was inserted with, so two
-- players with different records could both show rank 1.
select ok(not exists (
  select 1 from public.sabotage_draft_standings a
    join public.sabotage_draft_standings b
      on b.match_id = a.match_id and b.user_id <> a.user_id
   where a.match_id = (select v from tests.fx where k = 'm')
     and a.wins > b.wins and a.tiebreak_rank >= b.tiebreak_rank
), 'a strictly better record always gets a strictly better tiebreak_rank');

select * from finish();
rollback;
