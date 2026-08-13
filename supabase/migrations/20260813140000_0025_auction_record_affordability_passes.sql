-- An affordability skip is a real pass, not merely an omitted turn.  Keeping
-- it in the action log preserves replayability and lets the UI distinguish it
-- from both a deliberate pass and a timeout.

alter table public.auction_bids
  add column automatic boolean not null default false;

create or replace function private.auction_apply(p_match_id uuid, p_actor uuid, p_action text, p_amount numeric, p_by_timeout boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.auction_matches; v_status public.match_status; v_seq smallint; v_seat smallint; v_budget int;
  v_price int; v_high uuid; v_high_st smallint; v_live smallint[]; v_actionable smallint[]; v_n int; v_bid smallint; v_next smallint; v_try smallint; v_i int; v_winner uuid;
begin
  select * into v_board from public.auction_matches where match_id=p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode='P0001'; end if;
  select status into v_status from public.matches where id=p_match_id;
  if v_status <> 'playing'::public.match_status then raise exception 'match_not_playing' using errcode='P0001'; end if;
  if v_board.phase <> 'bidding' then raise exception 'bidding_not_open' using errcode='P0001'; end if;
  select seat,budget into v_seat,v_budget from public.auction_players where match_id=p_match_id and user_id=p_actor;
  if not found then raise exception 'not_a_participant' using errcode='42501'; end if;
  if v_board.turn_seat is null or v_board.turn_seat <> v_seat then raise exception 'not_your_turn' using errcode='P0001'; end if;
  v_seq:=v_board.current_lot;
  if exists(select 1 from public.auction_bids where match_id=p_match_id and seq=v_seq and user_id=p_actor and action='pass') then raise exception 'already_passed' using errcode='P0001'; end if;
  select b.user_id,b.price into v_high,v_price from public.auction_bids b where b.match_id=p_match_id and b.seq=v_seq and b.action='raise' order by b.bid_seq desc limit 1;
  v_price:=coalesce(v_price,0); select coalesce(max(bid_seq),0)+1 into v_bid from public.auction_bids where match_id=p_match_id and seq=v_seq;
  if p_action='raise' then
    if p_amount is null or p_amount <> trunc(p_amount) then raise exception 'bid_not_whole' using errcode='P0001'; end if;
    if p_amount <= v_price then raise exception 'bid_not_increasing' using errcode='P0001'; end if;
    if p_amount > v_budget then raise exception 'insufficient_budget' using errcode='P0001'; end if;
    if not private.auction_eligible(p_match_id,p_actor,v_seq) then raise exception 'not_eligible' using errcode='P0001'; end if;
    v_price:=p_amount::int; v_high:=p_actor;
    insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic)
      values (p_match_id,v_seq,v_bid,p_actor,'raise',v_price,p_by_timeout,now(),false);
  elsif p_action='pass' then
    insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic)
      values (p_match_id,v_seq,v_bid,p_actor,'pass',null,p_by_timeout,now(),false);
  else raise exception 'bad_action' using errcode='P0001'; end if;

  v_live:=private.auction_live_seats(p_match_id,v_seq);
  if v_high is not null then
    insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic)
    select p_match_id, v_seq, v_bid + row_number() over (order by ap.seat), ap.user_id,
           'pass', null, false, now(), true
      from public.auction_players ap
     where ap.match_id = p_match_id
       and ap.seat = any(v_live)
       and ap.user_id <> v_high
       and ap.budget <= v_price;
    v_live:=private.auction_live_seats(p_match_id,v_seq);
  end if;
  select count(*) into v_n from public.auction_players where match_id=p_match_id;

  if v_high is not null then
    select coalesce(array_agg(ap.seat order by ap.seat), '{}'::smallint[]) into v_actionable
      from public.auction_players ap
     where ap.match_id = p_match_id
       and (ap.user_id = v_high or (ap.seat = any(v_live) and ap.budget > v_price));
  else
    v_actionable := v_live;
  end if;

  if coalesce(array_length(v_actionable,1),0)<=1 then
    if v_high is not null then
      perform private.auction_resolve(p_match_id,v_seq,v_high,v_price);
    elsif coalesce(array_length(v_actionable,1),0)=1 then
      select user_id into v_winner from public.auction_players where match_id=p_match_id and seat=v_actionable[1];
      perform private.auction_resolve(p_match_id,v_seq,v_winner,0);
    else
      perform private.auction_resolve(p_match_id,v_seq,null,null);
    end if;
    return;
  end if;

  v_high_st:=null;
  if v_high is not null then
    select seat into v_high_st from public.auction_players where match_id=p_match_id and user_id=v_high;
  end if;
  for v_i in 1..v_n loop
    v_try:=((v_seat+v_i)%v_n)::smallint;
    if v_try=any(v_actionable) and v_try is distinct from v_high_st then
      v_next:=v_try;
      exit;
    end if;
  end loop;
  if v_next is null then raise exception 'no_next_bidder' using errcode='P0001'; end if;
  update public.auction_matches set turn_seat=v_next,turn_deadline=now()+interval '20 seconds' where match_id=p_match_id;
end;
$$;
