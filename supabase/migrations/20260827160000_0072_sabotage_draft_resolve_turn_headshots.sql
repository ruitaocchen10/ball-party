-- 0067 widened random_pick's return row with headshot_url and wired it into
-- submit_pick and expire(), but missed the third place a pick's identity
-- changes after it's first written: resolve_turn's own respin and sabotage
-- branches. Both UPDATE a pick's player_id/display_name/season in place
-- without touching headshot_url, so a respun or sabotaged card kept
-- displaying whoever's photo the original pick happened to have -- the
-- portrait and the name silently disagreeing for the rest of the match.
--
-- Restated whole from its current (0063) form, per the append-only rule.
create or replace function sabotage_draft_private.resolve_turn(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board     public.sabotage_draft_matches;
  v_round     public.sabotage_draft_rounds;
  v_active    uuid;
  v_franchise text;
  v_pick      public.sabotage_draft_picks;
  v_guess     record;
  v_drawn     record;
  v_exact     boolean;
  v_kind      text;
  v_result    sabotage_draft.guess_result;
begin
  select * into v_board from public.sabotage_draft_matches where match_id = p_match_id;
  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  select * into v_round from public.sabotage_draft_rounds
   where match_id = p_match_id and round_number = v_board.current_round;
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_active);

  for v_guess in
    select * from public.sabotage_draft_guesses
     where match_id = p_match_id and round_number = v_board.current_round
       and target_user_id = v_active and result is null
     order by id
  loop
    select * into v_pick from public.sabotage_draft_picks
     where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
    v_exact := v_pick.player_id = v_guess.player_id and (v_guess.season is null or v_pick.season = v_guess.season);
    v_kind := case when v_guess.season is null then 'respin' else 'sabotage' end;

    if v_exact and not exists (
      select 1 from public.sabotage_draft_pick_hits
       where match_id = p_match_id and round_number = v_board.current_round
         and target_user_id = v_active and kind = v_kind
    ) then
      insert into public.sabotage_draft_pick_hits (match_id, round_number, target_user_id, kind, guesser_user_id)
      values (p_match_id, v_board.current_round, v_active, v_kind, v_guess.user_id);

      if v_kind = 'respin' then
        select * into v_drawn from sabotage_draft_private.random_pick(
          v_franchise, sabotage_draft_private.pool_categories(v_round.slot)
        );
        update public.sabotage_draft_picks
           set player_id = v_drawn.player_id, display_name = v_drawn.display_name,
               season = v_drawn.season, headshot_url = v_drawn.headshot_url, by_timeout = false
         where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
        v_result := 'respun';
      else
        update public.sabotage_draft_picks
           set player_id = v_guess.replacement_player_id,
               display_name = (
                 select display_name from private.av_roster_players
                  where franchise_code = v_franchise
                    and player_id = v_guess.replacement_player_id
                    and season = v_guess.replacement_season
                    and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot))
               ),
               headshot_url = (
                 select headshot_url from private.av_player_headshots
                  where player_id = v_guess.replacement_player_id
               ),
               season = v_guess.replacement_season, by_timeout = false
         where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
        v_result := 'sabotaged';
      end if;
    else
      v_result := 'miss';
    end if;

    update public.sabotage_draft_guesses set result = v_result
     where match_id = p_match_id and round_number = v_board.current_round
       and target_user_id = v_active and user_id = v_guess.user_id;
  end loop;

  perform sabotage_draft_private.advance_turn(p_match_id);
end;
$$;
