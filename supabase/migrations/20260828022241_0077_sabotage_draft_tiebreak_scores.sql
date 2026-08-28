-- A tiebreak is presented as a playoff game, so persist its score alongside
-- its already-persisted winner. Nullable columns retain the ability to read
-- historic brackets that were simulated before scores existed; every new
-- played matchup writes both scores, while a bye writes neither.
alter table public.sabotage_draft_tiebreak_games
  add column player_a_score smallint,
  add column player_b_score smallint,
  add constraint sabotage_draft_tiebreak_games_scores_pair
    check ((player_a_score is null) = (player_b_score is null)),
  add constraint sabotage_draft_tiebreak_games_scores_distinct
    check (player_a_score is null or player_a_score <> player_b_score);

-- Keep the existing probability model as the decision that determines who
-- advances. Once that decision is made, draw a football-shaped winning score
-- and margin independently, then store the result in player A/B order. The
-- display can therefore show the exact game the bracket resolver used rather
-- than inventing a score in the browser after the fact.
create or replace function sabotage_draft_private.break_record_tie(
  p_match_id uuid, p_wins smallint, p_players uuid[], p_base_rank smallint
)
returns table (user_id uuid, tiebreak_rank smallint)
language plpgsql security definer set search_path = '' as $$
declare
  v_remaining uuid[] := p_players; v_next uuid[]; v_a uuid; v_b uuid;
  v_round smallint := 1; v_game smallint; v_i int;
  v_rank smallint := p_base_rank + array_length(p_players, 1) - 1;
  v_strength_a integer; v_strength_b integer; v_winner uuid;
  v_score_a smallint; v_score_b smallint; v_loser_score smallint; v_margin smallint;
begin
  while array_length(v_remaining, 1) > 1 loop
    select array_agg(u.user_id order by random()) into v_remaining
      from unnest(v_remaining) as u(user_id);
    v_next := array[]::uuid[]; v_game := 0;
    for v_i in 1 .. array_length(v_remaining, 1) by 2 loop
      v_game := v_game + 1; v_a := v_remaining[v_i]; v_b := v_remaining[v_i + 1];
      v_score_a := null; v_score_b := null;
      if v_b is null then
        v_winner := v_a;
      else
        select s.roster_strength into v_strength_a from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_a;
        select s.roster_strength into v_strength_b from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_b;
        v_winner := case when random() < sabotage_draft_private.win_probability(v_strength_a, v_strength_b) then v_a else v_b end;
        v_loser_score := (10 + floor(random() * 15))::smallint;
        v_margin := (1 + floor(random() * 14))::smallint;
        if v_winner = v_a then
          v_score_a := v_loser_score + v_margin; v_score_b := v_loser_score;
        else
          v_score_a := v_loser_score; v_score_b := v_loser_score + v_margin;
        end if;
      end if;
      insert into public.sabotage_draft_tiebreak_games
        (match_id, record_wins, bracket_round, game_number, player_a, player_b, winner_user_id, player_a_score, player_b_score)
      values (p_match_id, p_wins, v_round, v_game, v_a, v_b, v_winner, v_score_a, v_score_b);
      v_next := array_append(v_next, v_winner);
    end loop;
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
