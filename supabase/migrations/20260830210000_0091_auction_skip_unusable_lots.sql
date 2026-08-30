-- Do not preview a lot that nobody can legally add to their roster.
--
-- The dealer deliberately creates a small RB/WR/TE buffer for FLEX safety.
-- As rosters fill, a buffered card can become unusable before every other
-- position is complete. Resolving it as "No sale" makes players sit through a
-- card that was never a real choice. The next-lot selection owns that rule:
-- callers still only ask advance() to move the auction forward.

CREATE FUNCTION auction_private.next_usable_lot(
  p_match_id uuid,
  p_from_seq smallint
)
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select min(l.seq)
    from public.auction_lots l
   where l.match_id = p_match_id
     and l.seq >= p_from_seq
     and exists (
       select 1
         from public.auction_players ap
        where ap.match_id = p_match_id
          and auction_private.eligible(p_match_id, ap.user_id, l.seq)
     )
$function$
;

revoke all on function auction_private.next_usable_lot(uuid, smallint)
  from public, anon, authenticated;

CREATE OR REPLACE FUNCTION auction_private.advance(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_board public.auction_matches;
  v_scores jsonb;
  v_next_lot smallint;
begin
  select * into v_board from public.auction_matches where match_id = p_match_id;

  -- Scan the hidden remainder of the dealt deck before making a card visible.
  -- No bid/pass history exists for future lots, so eligibility alone tells us
  -- whether a card can still become part of any roster.
  if not auction_private.rosters_complete(p_match_id) then
    select auction_private.next_usable_lot(p_match_id, v_board.current_lot)
      into v_next_lot;
  end if;

  if v_next_lot is null then
    update public.auction_matches
       set turn_seat = null, turn_deadline = null, phase_deadline = null
     where match_id = p_match_id;
    select jsonb_object_agg(ap.user_id::text, coalesce(w.total, 0)) into v_scores
      from public.auction_players ap left join (
        select winner_id, sum(points) total from public.auction_lots
         where match_id = p_match_id and winner_id is not null group by winner_id
      ) w on w.winner_id = ap.user_id where ap.match_id = p_match_id;
    perform private.finish_match(p_match_id, v_scores);
    return;
  end if;

  update public.auction_matches
     set current_lot = v_next_lot,
         phase = 'lot_preview', phase_deadline = now() + interval '5 seconds',
         turn_seat = null, turn_deadline = null
   where match_id = p_match_id;
end;
$function$
;
