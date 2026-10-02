-- Hardening for the auction token abilities (0158-0160).
--
-- 1. Scout on season-total matches. 0159 refused outright because the weekly
--    PPR breakpoints mean nothing against a season total. A season lot's tier
--    is instead its position-relative percentile across the whole season pool
--    (private.player_seasons): bottom third rough, top quarter great, the rest
--    solid. Computed from the pool, not from the board, so the same card reads
--    the same tier whichever match it is dealt into.
--
-- 2. A timeout on the stuck seat used to call apply('pass'), which for that
--    seat means "decline with a token". With no token left (or an exhausted
--    redraw pool) apply raises, expire() raised with it, and sweep() -- which
--    had no handler -- aborted every other match's sweep too, so the match sat
--    on one screen forever. A timeout on the stuck seat now takes the free $0
--    claim instead: an idle player gets the lot they were handed, and never
--    has a token burned for them.
--
-- 3. sweep() never selected phase = 'sealed', so a sealed lot whose clock ran
--    out relied on a client calling expire_turn. It now does, and a failure in
--    one match is logged and skipped rather than blocking the rest.

-- ------------------------------------------------------------ season tiering --

create function auction_private.season_tier(p_position text, p_points numeric)
 returns text
 language sql
 stable
 set search_path to ''
as $function$
  select case
    when pct < 1.0/3 then 'rough'
    when pct >= 0.75 then 'great'
    else 'solid'
  end
  from (
    select (count(*) filter (where ps.points < p_points))::numeric / nullif(count(*), 0) as pct
      from private.player_seasons ps
     where ps.position = p_position
  ) s;
$function$;

revoke all on function auction_private.season_tier(text, numeric) from public, anon, authenticated;

create or replace function auction.use_scout_token(p_match_id uuid)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user       uuid := auth.uid();
  v_status     public.match_status;
  v_board      public.auction_matches;
  v_used_scout boolean;
  v_position   text;
  v_points     numeric(5,1);
  v_tier       text;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  select status into v_status from public.matches where id = p_match_id;
  if v_status is distinct from 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  select * into v_board from public.auction_matches where match_id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  if v_board.phase = 'sold' then raise exception 'lot_already_resolved' using errcode = 'P0001'; end if;

  select used_scout_token into v_used_scout
    from public.auction_players where match_id = p_match_id and user_id = v_user;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_used_scout or auction_private.tokens_used(p_match_id, v_user) >= v_board.token_count then
    raise exception 'no_scout_tokens' using errcode = 'P0001';
  end if;

  select position into v_position
    from public.auction_lots where match_id = p_match_id and seq = v_board.current_lot;
  if v_position is null then raise exception 'lot_not_found' using errcode = 'P0001'; end if;

  select points into v_points
    from private.auction_answers where match_id = p_match_id and seq = v_board.current_lot;

  v_tier := case v_board.scoring_mode
    when 'weekly' then auction_private.weekly_tier(v_position, v_points)
    else auction_private.season_tier(v_position, v_points)
  end;

  insert into public.auction_scouting_hints (match_id, seq, user_id, tier)
  values (p_match_id, v_board.current_lot, v_user, v_tier);

  update public.auction_players set used_scout_token = true
   where match_id = p_match_id and user_id = v_user;

  return v_tier;
end;
$function$;

-- -------------------------------------------------------------------- expire --

create or replace function auction_private.expire(p_match_id uuid)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
  if v_board.phase = 'sealed' then
    if v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;
    perform auction_private.resolve_sealed(p_match_id, v_board.current_lot);
    return true;
  end if;
  if v_board.phase <> 'bidding' or v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;
  select user_id into v_actor from public.auction_players where match_id=p_match_id and seat=v_board.turn_seat;
  if v_board.stuck_seat is not null and v_board.stuck_seat = v_board.turn_seat then
    -- Idle on the lot they were handed: take it for the free $0 claim rather
    -- than decline (which costs a token and can be refused outright).
    perform auction_private.apply(p_match_id,v_actor,'raise',0,true); return true;
  end if;
  perform auction_private.apply(p_match_id,v_actor,'pass',null,true); return true;
end;
$function$;

-- --------------------------------------------------------------------- sweep --

create or replace function auction_private.sweep()
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  r record;
  v_i int;
begin
  for r in
    select am.match_id
      from public.auction_matches am
      join public.matches mt on mt.id = am.match_id
     where mt.status = 'playing'::public.match_status
       and (
         (am.phase in ('bidding', 'sealed')
            and am.turn_deadline < now() - interval '1 minute')
         or (am.phase in ('lot_preview', 'sold')
            and am.phase_deadline < now() - interval '2 seconds')
       )
  loop
    begin
      for v_i in 1 .. 8 loop
        exit when not auction_private.expire(r.match_id);
      end loop;
    exception when others then
      raise warning 'auction sweep skipped match %: %', r.match_id, sqlerrm;
    end;
  end loop;

  for r in
    select mt.id
      from public.matches mt
      join public.runs rn on rn.id = mt.run_id
     where mt.status in (
             'setup'::public.match_status,
             'playing'::public.match_status,
             'paused'::public.match_status
           )
       and rn.status <> 'active'::public.run_status
  loop
    perform private.abandon_match(r.id);
  end loop;

  for r in
    select mt.id
      from public.matches mt
      join public.runs rn on rn.id = mt.run_id
     where mt.status = 'setup'::public.match_status
       and rn.started_at < now() - interval '10 minutes'
  loop
    perform private.abandon_match(r.id);
  end loop;
end;
$function$;

-- ------------------------------------------------------------- can_decline --

-- 5. A stuck seat's only real choice is claim-or-decline, and declining costs a
--    pass token. With none left there is nothing to decide, so waiting out the
--    20-second turn is dead time (e.g. broke, and the other team is full).
create function auction_private.can_decline(p_match_id uuid, p_user_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select not ap.used_pass_token and auction_private.tokens_used(p_match_id, p_user_id) < am.token_count
    from public.auction_players ap
    join public.auction_matches am on am.match_id = ap.match_id
   where ap.match_id = p_match_id and ap.user_id = p_user_id;
$function$;

revoke all on function auction_private.can_decline(uuid, uuid) from public, anon, authenticated;

-- --------------------------------------------------------------- open_bidding --

create or replace function auction_private.open_bidding(p_match_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_board public.auction_matches; v_live smallint[]; v_funded smallint[]; v_n int; v_opener smallint; v_turn smallint; v_probe int:=0;
begin
  select * into v_board from public.auction_matches where match_id=p_match_id for update;
  if not found or v_board.phase<>'lot_preview' then return; end if;
  v_live:=auction_private.live_seats(p_match_id,v_board.current_lot); select count(*) into v_n from public.auction_players where match_id=p_match_id;
  -- Exactly one eligible player for this lot and nobody has bid yet: instead
  -- of auto-winning it for them, give that seat a real turn (take it for $0,
  -- or burn a pass token to let it go unsold). Zero eligible players (below)
  -- is a different case -- nobody could ever take that lot, token or not.
  if coalesce(array_length(v_live,1),0)=1 then
    if auction_private.can_decline(p_match_id,(select user_id from public.auction_players where match_id=p_match_id and seat=v_live[1])) then
      update public.auction_matches
         set turn_seat=v_live[1], stuck_seat=v_live[1],
             turn_deadline=now()+interval '20 seconds', phase='bidding', phase_deadline=null
       where match_id=p_match_id;
    else
      perform auction_private.resolve(p_match_id,v_board.current_lot,(select user_id from public.auction_players where match_id=p_match_id and seat=v_live[1]),0);
    end if;
    return;
  end if;
  if coalesce(array_length(v_live,1),0)=0 then perform auction_private.resolve(p_match_id,v_board.current_lot,null,null); return; end if;
  v_opener:=v_board.opener_seat;
  while not (v_opener=any(v_live)) loop v_opener:=((v_opener+1)%v_n)::smallint; v_probe:=v_probe+1; if v_probe>v_n then raise exception 'no_eligible_opener' using errcode='P0001'; end if; end loop;
  select coalesce(array_agg(ap.seat order by ap.seat),'{}'::smallint[]) into v_funded from public.auction_players ap where ap.match_id=p_match_id and ap.seat=any(v_live) and ap.budget>0;
  if not (v_opener=any(v_funded)) then
    if coalesce(array_length(v_funded,1),0)=0 then perform auction_private.resolve(p_match_id,v_board.current_lot,(select user_id from public.auction_players where match_id=p_match_id and seat=v_opener),0); return; end if;
    v_turn:=v_opener; v_probe:=0;
    while true loop v_turn:=((v_turn+1)%v_n)::smallint; v_probe:=v_probe+1; exit when v_turn=any(v_funded); if v_probe>v_n then raise exception 'no_funded_bidder' using errcode='P0001'; end if; end loop;
    update public.auction_matches set opener_seat=v_opener,free_fallback_seat=v_opener,turn_seat=v_turn,turn_deadline=now()+interval '20 seconds',phase='bidding',phase_deadline=null where match_id=p_match_id; return;
  end if;
  update public.auction_matches set opener_seat=v_opener,free_fallback_seat=null,turn_seat=v_opener,turn_deadline=now()+interval '20 seconds',phase='bidding',phase_deadline=null where match_id=p_match_id;
end;
$$;

-- ----------------------------------------------------------------------- apply --

-- 4. A decline appends a redraw to the deck, and FLEX eligibility counts the
--    remaining lots of a position (eligible()), so the redraw can make a seat
--    that was ineligible a moment ago live on the *current* lot. apply then
--    hands the turn to that seat but left `stuck_seat` pointing at the player
--    who had just declined, so stuck_seat <> turn_seat. `stuck_seat = null` now
--    clears when the turn moves on. Also (5): the stuck turn is only worth
--    handing out if that seat can decline it (see can_decline); otherwise it
--    is a 20-second wait for a decision they cannot make, so the lot goes to
--    them at once, as it did before 0158.
create or replace function auction_private.apply(p_match_id uuid,p_actor uuid,p_action text,p_amount numeric,p_by_timeout boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_board public.auction_matches; v_status public.match_status; v_seq smallint; v_seat smallint; v_budget int; v_used_pass boolean; v_price int; v_high uuid; v_high_st smallint; v_live smallint[]; v_actionable smallint[]; v_n int; v_bid smallint; v_next smallint; v_try smallint; v_i int; v_winner uuid; v_free_claim boolean;
begin
  select * into v_board from public.auction_matches where match_id=p_match_id for update; if not found then raise exception 'match_not_found' using errcode='P0001'; end if;
  select status into v_status from public.matches where id=p_match_id; if v_status<>'playing'::public.match_status then raise exception 'match_not_playing' using errcode='P0001'; end if;
  if v_board.phase<>'bidding' then raise exception 'bidding_not_open' using errcode='P0001'; end if;
  select seat,budget,used_pass_token into v_seat,v_budget,v_used_pass from public.auction_players where match_id=p_match_id and user_id=p_actor; if not found then raise exception 'not_a_participant' using errcode='42501'; end if;
  if v_board.turn_seat is null or v_board.turn_seat<>v_seat then raise exception 'not_your_turn' using errcode='P0001'; end if;
  v_seq:=v_board.current_lot; if exists(select 1 from public.auction_bids where match_id=p_match_id and seq=v_seq and user_id=p_actor and action='pass') then raise exception 'already_passed' using errcode='P0001'; end if;
  select b.user_id,b.price into v_high,v_price from public.auction_bids b where b.match_id=p_match_id and b.seq=v_seq and b.action='raise' order by b.bid_seq desc limit 1; v_price:=coalesce(v_price,0); select coalesce(max(bid_seq),0)+1 into v_bid from public.auction_bids where match_id=p_match_id and seq=v_seq;
  -- A $0 claim with nothing yet bid is free whenever the board is handing
  -- this seat the lot by default -- the broke-opener fallback (existing) or
  -- the stuck-seat turn this migration adds (new).
  v_free_claim:=((v_board.free_fallback_seat is not null) or (v_board.stuck_seat is not null and v_board.stuck_seat=v_seat)) and v_high is null and p_amount=0;
  if p_action='raise' then
    if p_amount is null or p_amount<>trunc(p_amount) then raise exception 'bid_not_whole' using errcode='P0001'; end if;
    if not v_free_claim and p_amount<=v_price then raise exception 'bid_not_increasing' using errcode='P0001'; end if;
    if p_amount>v_budget then raise exception 'insufficient_budget' using errcode='P0001'; end if;
    if not auction_private.eligible(p_match_id,p_actor,v_seq) then raise exception 'not_eligible' using errcode='P0001'; end if;
    v_price:=p_amount::int; v_high:=p_actor; insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic) values (p_match_id,v_seq,v_bid,p_actor,'raise',v_price,p_by_timeout,now(),false);
  elsif p_action='pass' then
    -- Declining the lot the board is about to hand you for free costs a
    -- pass token -- the whole point of this migration. Every other pass
    -- (you're not the stuck seat) is unchanged and free, as it always was.
    if v_board.stuck_seat is not null and v_board.stuck_seat=v_seat then
      if v_used_pass or auction_private.tokens_used(p_match_id,p_actor)>=v_board.token_count then
        raise exception 'no_pass_tokens' using errcode='P0001';
      end if;
      -- Redraws before anything else below commits, so a pool-exhausted
      -- refusal here leaves the token unspent and no bid row behind.
      perform auction_private.redraw(p_match_id, (select position from public.auction_lots where match_id=p_match_id and seq=v_seq));
      update public.auction_players set used_pass_token=true where match_id=p_match_id and user_id=p_actor;
    end if;
    insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic) values (p_match_id,v_seq,v_bid,p_actor,'pass',null,p_by_timeout,now(),false);
    if v_board.free_fallback_seat is not null and v_high is null then
      v_live:=auction_private.live_seats(p_match_id,v_seq); select coalesce(array_agg(ap.seat order by ap.seat),'{}'::smallint[]) into v_actionable from public.auction_players ap where ap.match_id=p_match_id and ap.seat=any(v_live) and ap.seat<>v_board.free_fallback_seat and ap.budget>0;
      if coalesce(array_length(v_actionable,1),0)=0 then select user_id into v_winner from public.auction_players where match_id=p_match_id and seat=v_board.free_fallback_seat; perform auction_private.resolve(p_match_id,v_seq,v_winner,0); return; end if;
      select count(*) into v_n from public.auction_players where match_id=p_match_id; for v_i in 1..v_n loop v_try:=((v_seat+v_i)%v_n)::smallint; if v_try=any(v_actionable) then v_next:=v_try; exit; end if; end loop; update public.auction_matches set turn_seat=v_next,turn_deadline=now()+interval '20 seconds' where match_id=p_match_id; return;
    end if;
  else raise exception 'bad_action' using errcode='P0001'; end if;
  v_live:=auction_private.live_seats(p_match_id,v_seq);
  if v_high is not null then insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic) select p_match_id,v_seq,v_bid+row_number() over(order by ap.seat),ap.user_id,'pass',null,false,now(),true from public.auction_players ap where ap.match_id=p_match_id and ap.seat=any(v_live) and ap.user_id<>v_high and ap.budget<=v_price; v_live:=auction_private.live_seats(p_match_id,v_seq); end if;
  select count(*) into v_n from public.auction_players where match_id=p_match_id;
  if v_high is not null then select coalesce(array_agg(ap.seat order by ap.seat),'{}'::smallint[]) into v_actionable from public.auction_players ap where ap.match_id=p_match_id and (ap.user_id=v_high or (ap.seat=any(v_live) and ap.budget>v_price)); else v_actionable:=v_live; end if;
  if coalesce(array_length(v_actionable,1),0)<=1 then
    if v_high is not null then
      perform auction_private.resolve(p_match_id,v_seq,v_high,v_price);
    elsif coalesce(array_length(v_actionable,1),0)=1 then
      -- Nobody has bid and exactly one live seat remains: hand them a real
      -- turn (the stuck-seat path above/below) instead of resolving for
      -- them. They take it with a free $0 raise, or burn a token to pass.
      if auction_private.can_decline(p_match_id,(select user_id from public.auction_players where match_id=p_match_id and seat=v_actionable[1])) then
        update public.auction_matches set turn_seat=v_actionable[1], stuck_seat=v_actionable[1], turn_deadline=now()+interval '20 seconds' where match_id=p_match_id;
      else
        perform auction_private.resolve(p_match_id,v_seq,(select user_id from public.auction_players where match_id=p_match_id and seat=v_actionable[1]),0);
      end if;
    else
      perform auction_private.resolve(p_match_id,v_seq,null,null);
    end if;
    return;
  end if;
  v_high_st:=null; if v_high is not null then select seat into v_high_st from public.auction_players where match_id=p_match_id and user_id=v_high; end if; for v_i in 1..v_n loop v_try:=((v_seat+v_i)%v_n)::smallint; if v_try=any(v_actionable) and v_try is distinct from v_high_st then v_next:=v_try; exit; end if; end loop;
  if v_next is null then raise exception 'no_next_bidder' using errcode='P0001'; end if; update public.auction_matches set turn_seat=v_next,stuck_seat=null,turn_deadline=now()+interval '20 seconds' where match_id=p_match_id;
end;
$$;
