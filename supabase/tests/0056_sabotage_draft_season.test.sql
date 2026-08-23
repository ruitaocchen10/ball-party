-- A completed X-Factor phase atomically turns every final roster into a
-- deterministic season and resolves every record tie before the match ends.
begin;
select plan(10);

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
-- way through round fourteen.
update public.sabotage_draft_players set absent = true
 where match_id = (select v from tests.fx where k = 'm') and user_id = (select v from tests.fx where k = 'p2');
do $$
declare i int;
begin
  for i in 1 .. 14 loop
    update public.sabotage_draft_matches set pick_deadline = now() - interval '1 second'
     where match_id = (select v::uuid from tests.fx where k = 'm');
    perform sabotage_draft_private.expire((select v::uuid from tests.fx where k = 'm'));
    update public.sabotage_draft_matches set guess_deadline = now() - interval '1 second'
     where match_id = (select v::uuid from tests.fx where k = 'm');
    perform sabotage_draft_private.expire((select v::uuid from tests.fx where k = 'm'));
  end loop;
end $$;

select tests.act_as((select v from tests.fx where k = 'p0'));
select lives_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'QB') $$,
  (select v from tests.fx where k = 'm')), 'an X-Factor replacement remains a valid final roster');
select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, null) $$,
  (select v from tests.fx where k = 'm')), 'an X-Factor discard remains a valid final roster');
select tests.act_as((select v from tests.fx where k = 'p2'));
select lives_ok(format($$ select sabotage_draft.submit_x_factor_decision(%L, 'WR1') $$,
  (select v from tests.fx where k = 'm')), 'the last decision triggers the season simulation');

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

select * from finish();
rollback;
