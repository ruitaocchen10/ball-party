-- Pacing, retuned after playtesting, and a janitor that stops being the thing
-- players wait on.
--
-- The measured problem was never the phase lengths. A lot nobody bid on
-- resolved in 5-6s and a lot that ran its full turn took 16s -- both correct.
-- But three lots in one game took 81s, 127s and 271s, and one of those had no
-- player actions at all. Nothing about a turn timer explains a 127-second lot
-- with nobody acting: the phase transition simply stalled, and the sweep below
-- was the only thing that ever moved it, one minute of grace later.
--
-- The client half of that fix lives in components/auction/AuctionMatch.tsx: it
-- now retries expiry instead of trying exactly once and latching. This file
-- fixes the other half -- a backstop that waits a full minute before rescuing a
-- phase with no human in it.

-- Preview 3s -> 5s, turn 10s -> 20s, sold 1.2s -> 5s. Longer on purpose: ten
-- seconds was not enough to price a lot you have never seen, and 1.2s was not
-- enough to read the number you had just paid for.

create or replace function private.auction_advance(p_match_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.auction_matches;
  v_scores jsonb;
begin
  select * into v_board from public.auction_matches where match_id = p_match_id;
  if v_board.current_lot > v_board.lot_count then
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
     set phase = 'lot_preview', phase_deadline = now() + interval '5 seconds',
         turn_seat = null, turn_deadline = null
   where match_id = p_match_id;
end;
$$;

create or replace function private.auction_open_bidding(p_match_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.auction_matches;
  v_live smallint[];
  v_n int;
  v_seat smallint;
  v_probe int := 0;
begin
  select * into v_board from public.auction_matches where match_id = p_match_id for update;
  if not found or v_board.phase <> 'lot_preview' then return; end if;
  v_live := private.auction_live_seats(p_match_id, v_board.current_lot);
  select count(*) into v_n from public.auction_players where match_id = p_match_id;
  if coalesce(array_length(v_live, 1), 0) = 1 then
    perform private.auction_resolve(p_match_id, v_board.current_lot,
      (select user_id from public.auction_players where match_id = p_match_id and seat = v_live[1]), 0);
    return;
  elsif coalesce(array_length(v_live, 1), 0) = 0 then
    perform private.auction_resolve(p_match_id, v_board.current_lot, null, null);
    return;
  end if;
  v_seat := v_board.opener_seat;
  while not (v_seat = any(v_live)) loop
    v_seat := ((v_seat + 1) % v_n)::smallint; v_probe := v_probe + 1;
    if v_probe > v_n then raise exception 'no_eligible_opener' using errcode = 'P0001'; end if;
  end loop;
  update public.auction_matches
     set opener_seat = v_seat, turn_seat = v_seat, turn_deadline = now() + interval '20 seconds',
         phase = 'bidding', phase_deadline = null
   where match_id = p_match_id;
end;
$$;

create or replace function private.auction_resolve(p_match_id uuid, p_seq smallint, p_winner uuid, p_price int)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_winner is not null then
    update public.auction_players set budget = budget - p_price where match_id = p_match_id and user_id = p_winner;
  end if;
  update public.auction_lots l set winner_id = p_winner, price = p_price,
    slot = case when p_winner is null then null when l.is_flex then 'FLEX' else l.position end,
    resolved_at = now(), points = (select a.points from private.auction_answers a where a.match_id=l.match_id and a.seq=l.seq)
  where l.match_id=p_match_id and l.seq=p_seq;
  update public.auction_matches set turn_seat = null, turn_deadline = null,
    phase = 'sold', phase_deadline = now() + interval '5 seconds' where match_id = p_match_id;
end;
$$;

create or replace function private.auction_apply(p_match_id uuid, p_actor uuid, p_action text, p_amount numeric, p_by_timeout boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.auction_matches; v_status public.match_status; v_seq smallint; v_seat smallint; v_budget int;
  v_price int; v_high uuid; v_high_st smallint; v_live smallint[]; v_n int; v_bid smallint; v_next smallint; v_try smallint; v_i int; v_winner uuid;
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
    -- Well-formedness before value: a bid of $3.50 is refused for its shape,
    -- not for how it compares to the price.
    if p_amount is null or p_amount <> trunc(p_amount) then raise exception 'bid_not_whole' using errcode='P0001'; end if;
    if p_amount <= v_price then raise exception 'bid_not_increasing' using errcode='P0001'; end if;
    if p_amount > v_budget then raise exception 'insufficient_budget' using errcode='P0001'; end if;
    if not private.auction_eligible(p_match_id,p_actor,v_seq) then raise exception 'not_eligible' using errcode='P0001'; end if;
    v_price:=p_amount::int; v_high:=p_actor;
    insert into public.auction_bids values (p_match_id,v_seq,v_bid,p_actor,'raise',v_price,p_by_timeout,now());
  elsif p_action='pass' then
    insert into public.auction_bids values (p_match_id,v_seq,v_bid,p_actor,'pass',null,p_by_timeout,now());
  else raise exception 'bad_action' using errcode='P0001'; end if;
  v_live:=private.auction_live_seats(p_match_id,v_seq); select count(*) into v_n from public.auction_players where match_id=p_match_id;
  if coalesce(array_length(v_live,1),0)<=1 then
    if coalesce(array_length(v_live,1),0)=1 then select user_id into v_winner from public.auction_players where match_id=p_match_id and seat=v_live[1]; perform private.auction_resolve(p_match_id,v_seq,v_winner,case when v_high=v_winner then v_price else 0 end);
    else perform private.auction_resolve(p_match_id,v_seq,null,null); end if;
    return;
  end if;
  v_high_st:=null; if v_high is not null then select seat into v_high_st from public.auction_players where match_id=p_match_id and user_id=v_high; end if;
  for v_i in 1..v_n loop v_try:=((v_seat+v_i)%v_n)::smallint; if v_try=any(v_live) and v_try is distinct from v_high_st then v_next:=v_try; exit; end if; end loop;
  if v_next is null then raise exception 'no_next_bidder' using errcode='P0001'; end if;
  update public.auction_matches set turn_seat=v_next,turn_deadline=now()+interval '20 seconds' where match_id=p_match_id;
end;
$$;

-- The grace is split by phase, because the two phases are owed different things.
--
-- A minute of grace on a live turn protects a real person whose network
-- hiccupped: cutting their decision short because a packet was late is the
-- failure worth paying a minute to avoid. A lot_preview or a sold
-- acknowledgement contains no decision and no person -- it is a timer that has
-- already run out. There is nothing there to protect, and waiting a minute to
-- notice is how a lot with zero player actions took 127 seconds.
create or replace function private.auction_sweep()
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
         (am.phase = 'bidding'
            and am.turn_deadline < now() - interval '1 minute')
         or (am.phase in ('lot_preview', 'sold')
            and am.phase_deadline < now() - interval '2 seconds')
       )
  loop
    for v_i in 1 .. 8 loop
      exit when not private.auction_expire(r.match_id);
    end loop;
  end loop;

  for r in
    select mt.id
      from public.matches mt
      join public.runs rn on rn.id = mt.run_id
     where mt.status in ('setup'::public.match_status, 'playing'::public.match_status)
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
$$;
