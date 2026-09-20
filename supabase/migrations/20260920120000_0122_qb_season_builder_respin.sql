-- QB Season Builder: the respin. See issue #74. The deal is 0120, picking 0121.
--
-- One respin per run. It rerolls the WHOLE spin — team and year together — it
-- is final, and it can be used at the start of any round, so the player decides
-- when to spend it. "Start of a round" needs no check of its own: picking closes
-- a round and deals the next in the same transaction, so a run is only ever
-- between picks, never mid-round.
--
-- The reroll cannot land on the spin it replaces. Nothing in the rules says so,
-- but a respin that can hand back the same team-season is a spent, final
-- decision that changed nothing, which is not the gamble the game describes.
--
-- The spin it replaces is kept (attempt 1) rather than overwritten. The player
-- saw it, and a hidden run reveals the values of every option the player was
-- shown once it is complete, the passed-over ones included.
--
-- Errors are the contract with the client, matched by message:
--   not_authenticated, match_not_found, wrong_game, not_a_participant,
--   match_not_playing   as for pick (0121)
--   draft_complete      every slot is filled: there is no spin left to reroll
--   respin_used         the run's one respin is already spent
create function qb_season_builder.respin(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_run   public.qb_season_builder_matches;
  v_spin  public.qb_season_builder_spins;
  v_next  record;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_run := qb_season_builder_private.lock_playing_run(p_match_id, v_user);

  if v_run.drafted_at is not null then
    raise exception 'draft_complete' using errcode = 'P0001';
  end if;

  if v_run.respin_used then
    raise exception 'respin_used' using errcode = 'P0001';
  end if;

  -- The respin is unspent, so the spin in play is the round's only one.
  v_spin := qb_season_builder_private.current_spin_of(p_match_id, v_run.current_round);

  select * into v_next
    from qb_season_builder_private.draw_spin(v_spin.franchise_code, v_spin.season);

  insert into public.qb_season_builder_spins (match_id, round_number, attempt, franchise_code, season)
  values (p_match_id, v_run.current_round, 2, v_next.franchise_code, v_next.season);

  update public.qb_season_builder_matches
     set respin_used = true
   where match_id = p_match_id;

  return qb_season_builder_private.board_of(p_match_id);
end;
$$;

revoke all on function qb_season_builder.respin(uuid) from public, anon;
grant execute on function qb_season_builder.respin(uuid) to authenticated;
