-- The name-only guess's "respin" used to void the whole pick and draw a
-- brand-new random player *and* year from the target's entire franchise/
-- position pool -- so a guesser who only knew *who* the pick was, not
-- *when*, could still cost the target their entire card. That made naming
-- the year worth almost nothing beyond the exact-guess branch's own reward:
-- the name-only guess already did nearly as much damage.
--
-- The respin now stays on the same player and only re-rolls their season,
-- drawn from that player's other years in the same franchise/category pool.
-- Getting the name right no longer erases who the target picked -- it costs
-- them the specific year, which is exactly the information the guesser
-- didn't have. Naming the year too is still the only way to choose the
-- replacement yourself (the 'sabotage' branch, unchanged).
--
-- A player with only one season in that pool has no other year to respin
-- to. Rather than falling back to a full random draw (which would just
-- reintroduce the old "cost them everything" outcome for exactly the
-- players a guesser is likeliest to have identified by playing it safe),
-- the guess simply misses: the pick stands untouched and no hit is
-- recorded, leaving the per-turn cap open for a guess that can actually
-- land.
create function sabotage_draft_private.random_pick_same_player(
  p_franchise_code text,
  p_categories text[],
  p_player_id text,
  p_exclude_season smallint,
  out player_id text,
  out display_name text,
  out season smallint,
  out headshot_url text
)
language sql
security definer
set search_path = ''
as $$
  select r.player_id, r.display_name, r.season, h.headshot_url
    from private.av_roster_players r
    left join private.av_player_headshots h on h.player_id = r.player_id
   where r.franchise_code = p_franchise_code
     and r.slot_category = any(p_categories)
     and r.player_id = p_player_id
     and r.season <> p_exclude_season
   order by random()
   limit 1;
$$;

-- Postgres grants EXECUTE on a new function to PUBLIC by default -- restate
-- the same revoke every sibling engine helper in this schema carries, for
-- the reason 0067's own comment on random_pick gives.
revoke all on function sabotage_draft_private.random_pick_same_player(text, text[], text, smallint)
  from public, anon, authenticated;

-- Restated whole from its current (0072) form, per the append-only rule.
-- Only the respin branch changes: it now looks for another season of the
-- *same* player before touching the pick, and does nothing at all if there
-- isn't one.
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
