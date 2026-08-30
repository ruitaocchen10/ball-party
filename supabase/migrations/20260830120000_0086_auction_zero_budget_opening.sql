-- A bankrupt rotating opener must never consume a decision timer.  They remain
-- the free fallback if funded challengers decline; when nobody can bid, the
-- rotating opener receives the lot for $0 immediately.

alter table public.auction_matches add column free_fallback_seat smallint;
alter type auction.turn add attribute free_fallback_seat smallint;

create or replace function auction_private.turn_of(p_match_id uuid) returns auction.turn language sql security definer set search_path='' stable as $$
  select (m.match_id,m.lot_count,m.current_lot,m.turn_seat,m.opener_seat,m.turn_deadline,now(),m.phase,m.phase_deadline,m.free_fallback_seat)::auction.turn from public.auction_matches m where m.match_id=p_match_id;
$$;

create or replace function auction_private.resolve(p_match_id uuid,p_seq smallint,p_winner uuid,p_price integer) returns void language plpgsql security definer set search_path='' as $$
begin
  if p_winner is not null then update public.auction_players set budget=budget-p_price where match_id=p_match_id and user_id=p_winner; end if;
  update public.auction_lots l set winner_id=p_winner,price=p_price,slot=case when p_winner is null then null when l.is_flex then 'FLEX' else l.position end,resolved_at=now(),points=(select a.points from private.auction_answers a where a.match_id=l.match_id and a.seq=l.seq) where l.match_id=p_match_id and l.seq=p_seq;
  update public.auction_matches set turn_seat=null,turn_deadline=null,free_fallback_seat=null,phase='sold',phase_deadline=now()+interval '5 seconds' where match_id=p_match_id;
end;
$$;

create or replace function auction_private.open_bidding(p_match_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_board public.auction_matches; v_live smallint[]; v_funded smallint[]; v_n int; v_opener smallint; v_turn smallint; v_probe int:=0;
begin
  select * into v_board from public.auction_matches where match_id=p_match_id for update;
  if not found or v_board.phase<>'lot_preview' then return; end if;
  v_live:=auction_private.live_seats(p_match_id,v_board.current_lot); select count(*) into v_n from public.auction_players where match_id=p_match_id;
  if coalesce(array_length(v_live,1),0)=1 then perform auction_private.resolve(p_match_id,v_board.current_lot,(select user_id from public.auction_players where match_id=p_match_id and seat=v_live[1]),0); return; end if;
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

create or replace function auction_private.apply(p_match_id uuid,p_actor uuid,p_action text,p_amount numeric,p_by_timeout boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_board public.auction_matches; v_status public.match_status; v_seq smallint; v_seat smallint; v_budget int; v_price int; v_high uuid; v_high_st smallint; v_live smallint[]; v_actionable smallint[]; v_n int; v_bid smallint; v_next smallint; v_try smallint; v_i int; v_winner uuid; v_free_claim boolean;
begin
  select * into v_board from public.auction_matches where match_id=p_match_id for update; if not found then raise exception 'match_not_found' using errcode='P0001'; end if;
  select status into v_status from public.matches where id=p_match_id; if v_status<>'playing'::public.match_status then raise exception 'match_not_playing' using errcode='P0001'; end if;
  if v_board.phase<>'bidding' then raise exception 'bidding_not_open' using errcode='P0001'; end if;
  select seat,budget into v_seat,v_budget from public.auction_players where match_id=p_match_id and user_id=p_actor; if not found then raise exception 'not_a_participant' using errcode='42501'; end if;
  if v_board.turn_seat is null or v_board.turn_seat<>v_seat then raise exception 'not_your_turn' using errcode='P0001'; end if;
  v_seq:=v_board.current_lot; if exists(select 1 from public.auction_bids where match_id=p_match_id and seq=v_seq and user_id=p_actor and action='pass') then raise exception 'already_passed' using errcode='P0001'; end if;
  select b.user_id,b.price into v_high,v_price from public.auction_bids b where b.match_id=p_match_id and b.seq=v_seq and b.action='raise' order by b.bid_seq desc limit 1; v_price:=coalesce(v_price,0); select coalesce(max(bid_seq),0)+1 into v_bid from public.auction_bids where match_id=p_match_id and seq=v_seq;
  v_free_claim:=v_board.free_fallback_seat is not null and v_high is null and p_amount=0;
  if p_action='raise' then
    if p_amount is null or p_amount<>trunc(p_amount) then raise exception 'bid_not_whole' using errcode='P0001'; end if;
    if not v_free_claim and p_amount<=v_price then raise exception 'bid_not_increasing' using errcode='P0001'; end if;
    if p_amount>v_budget then raise exception 'insufficient_budget' using errcode='P0001'; end if;
    if not auction_private.eligible(p_match_id,p_actor,v_seq) then raise exception 'not_eligible' using errcode='P0001'; end if;
    v_price:=p_amount::int; v_high:=p_actor; insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic) values (p_match_id,v_seq,v_bid,p_actor,'raise',v_price,p_by_timeout,now(),false);
  elsif p_action='pass' then
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
  if coalesce(array_length(v_actionable,1),0)<=1 then if v_high is not null then perform auction_private.resolve(p_match_id,v_seq,v_high,v_price); elsif coalesce(array_length(v_actionable,1),0)=1 then select user_id into v_winner from public.auction_players where match_id=p_match_id and seat=v_actionable[1]; perform auction_private.resolve(p_match_id,v_seq,v_winner,0); else perform auction_private.resolve(p_match_id,v_seq,null,null); end if; return; end if;
  v_high_st:=null; if v_high is not null then select seat into v_high_st from public.auction_players where match_id=p_match_id and user_id=v_high; end if; for v_i in 1..v_n loop v_try:=((v_seat+v_i)%v_n)::smallint; if v_try=any(v_actionable) and v_try is distinct from v_high_st then v_next:=v_try; exit; end if; end loop;
  if v_next is null then raise exception 'no_next_bidder' using errcode='P0001'; end if; update public.auction_matches set turn_seat=v_next,turn_deadline=now()+interval '20 seconds' where match_id=p_match_id;
end;
$$;
