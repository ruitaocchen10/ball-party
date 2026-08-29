-- auction_private.expire's missing pause guard.
--
-- 0061's comment claims every player-action RPC already gates on
-- `mt.status = 'playing'`, citing auction_private.apply's `match_not_playing`
-- check -- but expire's `lot_preview`/`sold` branches call open_bidding/
-- advance directly, bypassing apply entirely, so that gate never actually
-- covered them. sabotage_draft_private.expire and higher_or_lower_private
-- .expire both already join public.matches and require 'playing' before
-- touching anything; this brings auction's expire in line with that same
-- convention. Without it, a stray auction.expire_turn call landing while a
-- match is paused can set a fresh, real-time-based deadline that resume_match
-- then shifts forward *again* by the whole pause duration, on top of one
-- that was never stale to begin with.
CREATE OR REPLACE FUNCTION auction_private.expire(p_match_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_board public.auction_matches; v_actor uuid; v_n int;
begin
  select am.* into v_board from public.auction_matches am join public.matches mt on mt.id = am.match_id
   where am.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of am;
  if not found then return false; end if;
  if v_board.phase='lot_preview' and v_board.phase_deadline <= now() then perform auction_private.open_bidding(p_match_id); return true; end if;
  if v_board.phase='sold' and v_board.phase_deadline <= now() then
    select count(*) into v_n from public.auction_players where match_id=p_match_id;
    update public.auction_matches set current_lot=current_lot+1,opener_seat=((opener_seat+1)%v_n)::smallint where match_id=p_match_id;
    perform auction_private.advance(p_match_id); return true;
  end if;
  if v_board.phase <> 'bidding' or v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;
  select user_id into v_actor from public.auction_players where match_id=p_match_id and seat=v_board.turn_seat;
  perform auction_private.apply(p_match_id,v_actor,'pass',null,true); return true;
end;
$function$
;
