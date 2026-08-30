-- Two guessers can both be right about the same pick in the same turn: one
-- names just the player, the other names the player and the exact season.
-- Guesses used to resolve in submission order (`order by id`) regardless of
-- kind, so whichever guess reached the database first mutated the pick out
-- from under the other -- a name-only guess that landed first would respin
-- the season before the exact guess was even checked, costing the harder,
-- more informed guess its hit for no reason but network timing.
--
-- The exact guess (naming the player *and* the season) is strictly harder to
-- land than the name-only guess, so it now always resolves first within a
-- turn, whichever guesser submitted later. Two guesses of the same kind
-- still tie-break on submission order, same as before -- the change is only
-- sabotage-before-respin, not a full reordering.
--
-- Restated whole from its current (0075) form, per the append-only rule.
-- Only the ordering of the guess loop changes.
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
     -- Exact (season not null) guesses resolve before name-only (season
     -- null) ones -- `season is null` is false for an exact guess, and
     -- false sorts before true ascending -- then by submission order within
     -- the same kind.
     order by (season is null), id
  loop
    select * into v_pick from public.sabotage_draft_picks
     where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
    v_exact := v_pick.player_id = v_guess.player_id and (v_guess.season is null or v_pick.season = v_guess.season);
    v_kind := case when v_guess.season is null then 'respin' else 'sabotage' end;

    if v_exact and v_kind = 'respin' then
      -- The hit isn't recorded until it's known there's actually a
      -- different year to land on -- a guess that can't change anything
      -- shouldn't spend the turn's one respin slot.
      select * into v_drawn from sabotage_draft_private.random_pick_same_player(
        v_franchise, sabotage_draft_private.pool_categories(v_round.slot),
        v_pick.player_id, v_pick.season
      );
      v_exact := found;
    end if;

    if v_exact and not exists (
      select 1 from public.sabotage_draft_pick_hits
       where match_id = p_match_id and round_number = v_board.current_round
         and target_user_id = v_active and kind = v_kind
    ) then
      insert into public.sabotage_draft_pick_hits (match_id, round_number, target_user_id, kind, guesser_user_id)
      values (p_match_id, v_board.current_round, v_active, v_kind, v_guess.user_id);

      if v_kind = 'respin' then
        update public.sabotage_draft_picks
           set season = v_drawn.season, display_name = v_drawn.display_name,
               headshot_url = v_drawn.headshot_url, by_timeout = false
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
