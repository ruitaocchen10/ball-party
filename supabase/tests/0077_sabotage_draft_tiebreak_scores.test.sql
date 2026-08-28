-- Every newly resolved tiebreak game carries the actual simulated score that
-- decided it. The client can render a real scoreboard without manufacturing
-- a result from the winner after the fact.
begin;
select plan(4);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(2, 0.41));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;

select tests.act_as_admin();
insert into public.sabotage_draft_standings (match_id, user_id, roster_strength, wins, losses, tiebreak_rank)
  select (select v from tests.fx where k = 'm'), v, 93, 10, 7, 1
    from tests.fx where k in ('p0', 'p1');

select setseed(0.41);
select lives_ok(format($$
  select sabotage_draft_private.break_record_tie(
    %L, 10, array[%L::uuid, %L::uuid], 1
  )
$$, (select v from tests.fx where k = 'm'), (select v from tests.fx where k = 'p0'), (select v from tests.fx where k = 'p1')),
  'the tied pair resolves through one scored playoff game');

select is((select count(*)::int from public.sabotage_draft_tiebreak_games
  where match_id = (select v from tests.fx where k = 'm')), 1,
  'one actual matchup is stored for the tied pair');

select ok((select player_a_score is not null and player_b_score is not null and player_a_score <> player_b_score
  from public.sabotage_draft_tiebreak_games where match_id = (select v from tests.fx where k = 'm')),
  'a played matchup stores two different scores');

select ok((select case when winner_user_id = player_a then player_a_score > player_b_score else player_b_score > player_a_score end
  from public.sabotage_draft_tiebreak_games where match_id = (select v from tests.fx where k = 'm')),
  'the higher score always belongs to the persisted winner');

select * from finish();
rollback;
