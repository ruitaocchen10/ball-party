-- The browser needs a round's eligible names to make a pick or a guess, but
-- the AV pool remains private: AV is scoring input, not client state.
create function sabotage_draft.options(p_match_id uuid)
returns table (player_id text, display_name text, season smallint, slot_category text)
language plpgsql stable security definer set search_path = '' as $$
declare v_round public.sabotage_draft_rounds;
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  select r.* into v_round from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r on r.match_id=m.match_id and r.round_number=m.current_round
    where m.match_id=p_match_id;
  return query
    select p.player_id, p.display_name, p.season, p.slot_category
      from private.av_roster_players p
     where p.franchise_code=v_round.franchise_code
       and p.slot_category=any(sabotage_draft_private.pool_categories(v_round.slot))
     order by p.display_name, p.season;
end;
$$;

revoke all on function sabotage_draft.options(uuid) from public, anon;
grant execute on function sabotage_draft.options(uuid) to authenticated;
