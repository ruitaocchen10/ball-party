-- simulate_season only ever assigned tiebreak_rank via break_record_tie,
-- which is called exclusively for players who share the exact same win
-- count. Every other player's tiebreak_rank was left at the literal 1 it
-- was inserted with, so any two players with different win totals could
-- both show rank 1 in the final standings -- the common case, not an edge
-- case, since most matches don't end in a full win-count tie.
--
-- The fix: rank every player first by how many others strictly out-won
-- them (1 + that count), which is already correct for anyone with a unique
-- win total. break_record_tie then only needs to refine ranks *within* a
-- tied win-count group, starting from that group's own base rank instead
-- of always starting the group at 1.

drop function if exists sabotage_draft_private.break_record_tie(uuid, smallint, uuid[]);

create function sabotage_draft_private.break_record_tie(
  p_match_id uuid, p_wins smallint, p_players uuid[], p_base_rank smallint
)
returns table (user_id uuid, tiebreak_rank smallint)
language plpgsql security definer set search_path = '' as $$
declare
  v_remaining uuid[] := p_players; v_next uuid[]; v_a uuid; v_b uuid;
  v_round smallint := 1; v_game smallint; v_i int;
  v_rank smallint := p_base_rank + array_length(p_players, 1) - 1;
  v_strength_a integer; v_strength_b integer; v_winner uuid;
begin
  while array_length(v_remaining, 1) > 1 loop
    select array_agg(u.user_id order by random()) into v_remaining
      from unnest(v_remaining) as u(user_id);
    v_next := array[]::uuid[]; v_game := 0;
    for v_i in 1 .. array_length(v_remaining, 1) by 2 loop
      v_game := v_game + 1; v_a := v_remaining[v_i]; v_b := v_remaining[v_i + 1];
      if v_b is null then
        v_winner := v_a;
      else
        select s.roster_strength into v_strength_a from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_a;
        select s.roster_strength into v_strength_b from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_b;
        v_winner := case when random() < sabotage_draft_private.win_probability(v_strength_a, v_strength_b) then v_a else v_b end;
      end if;
      insert into public.sabotage_draft_tiebreak_games
        (match_id, record_wins, bracket_round, game_number, player_a, player_b, winner_user_id)
      values (p_match_id, p_wins, v_round, v_game, v_a, v_b, v_winner);
      v_next := array_append(v_next, v_winner);
    end loop;
    -- Everyone eliminated in this layer shares its next rank.  The winner is
    -- overwritten by a better rank on a later layer (ultimately p_base_rank).
    update public.sabotage_draft_standings s set tiebreak_rank = v_rank
     where s.match_id = p_match_id and s.user_id = any(v_remaining) and s.user_id <> all(v_next);
    v_remaining := v_next; v_rank := v_rank - array_length(v_next, 1); v_round := v_round + 1;
  end loop;
  update public.sabotage_draft_standings s set tiebreak_rank = p_base_rank
   where s.match_id = p_match_id and s.user_id = v_remaining[1];
  return query select s.user_id, s.tiebreak_rank from public.sabotage_draft_standings s
   where s.match_id = p_match_id and s.user_id = any(p_players);
end;
$$;

create or replace function sabotage_draft_private.simulate_season(p_match_id uuid, p_seed double precision default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_seed double precision; v_mean integer; v_player record; v_game int; v_wins smallint;
  v_tie record;
begin
  select coalesce(p_seed, b.seed) into v_seed from sabotage_draft_private.boards b where b.match_id = p_match_id;
  if v_seed is null then raise exception 'board_not_found' using errcode = 'P0001'; end if;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  select round(avg(roster_strength))::integer into v_mean from sabotage_draft_private.roster_strengths(p_match_id);
  if v_mean is null then raise exception 'incomplete_roster' using errcode = 'P0001'; end if;
  for v_player in select * from sabotage_draft_private.roster_strengths(p_match_id) order by user_id loop
    v_wins := 0;
    for v_game in 1 .. 17 loop
      if random() < sabotage_draft_private.win_probability(v_player.roster_strength, v_mean) then v_wins := v_wins + 1; end if;
    end loop;
    insert into public.sabotage_draft_standings (match_id, user_id, roster_strength, wins, losses, tiebreak_rank)
    values (p_match_id, v_player.user_id, v_player.roster_strength, v_wins, 17 - v_wins, 1);
  end loop;
  insert into sabotage_draft_private.seasons (match_id, seed) values (p_match_id, v_seed);
  -- Table-wide starting rank for every player's win tier: 1 plus however many
  -- other players strictly out-won them. Correct as-is for anyone whose win
  -- count is unique; break_record_tie below only needs to spread the players
  -- who share a tier across that tier's own rank range.
  update public.sabotage_draft_standings s set tiebreak_rank = 1 + (
    select count(*) from public.sabotage_draft_standings o
     where o.match_id = p_match_id and o.wins > s.wins
  ) where s.match_id = p_match_id;
  for v_tie in select wins, array_agg(user_id order by user_id) as players, min(tiebreak_rank) as base_rank
                  from public.sabotage_draft_standings where match_id = p_match_id
                 group by wins having count(*) > 1 loop
    perform sabotage_draft_private.break_record_tie(p_match_id, v_tie.wins, v_tie.players, v_tie.base_rank);
  end loop;
  perform private.finish_match(p_match_id, (
    select jsonb_object_agg(user_id::text, (wins * 1000 + (100 - tiebreak_rank))::numeric)
      from public.sabotage_draft_standings where match_id = p_match_id
  ));
end;
$$;

revoke all on function sabotage_draft_private.break_record_tie(uuid, smallint, uuid[], smallint) from public, anon, authenticated;
