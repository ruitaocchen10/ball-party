-- The auction has one durable rhythm.  A phase belongs to the match, not a
-- browser: clients render a countdown from phase_deadline but only this file
-- decides when a preview becomes actionable or a sale becomes the next lot.

alter table public.auction_matches
  add column phase text not null default 'lot_preview'
    check (phase in ('lot_preview', 'bidding', 'sold')),
  add column phase_deadline timestamptz;

alter type public.auction_turn add attribute phase text;
alter type public.auction_turn add attribute phase_deadline timestamptz;

-- A newly dealt board is always introduced before anyone can act.
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
     set phase = 'lot_preview', phase_deadline = now() + interval '3 seconds',
         turn_seat = null, turn_deadline = null
   where match_id = p_match_id;
end;
$$;

-- Called after the shared three-second preview.  Automatic awards still pass
-- through preview, then hold their own sold acknowledgement.
create function private.auction_open_bidding(p_match_id uuid)
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
     set opener_seat = v_seat, turn_seat = v_seat, turn_deadline = now() + interval '10 seconds',
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
    phase = 'sold', phase_deadline = now() + interval '1.2 seconds' where match_id = p_match_id;
end;
$$;

-- Exact amounts are validated as amounts, never converted into a nearby bid.
--
-- Dropped rather than replaced: 0011 named this parameter p_increment, and
-- Postgres refuses to rename an input parameter through CREATE OR REPLACE.  The
-- amount arrives as numeric so that a fractional bid can be REJECTED rather
-- than silently rounded into a legal one by the int cast at the call boundary
-- -- which would be exactly the clamping this contract exists to forbid.
drop function private.auction_apply(uuid, uuid, text, int, boolean);

create function private.auction_apply(p_match_id uuid, p_actor uuid, p_action text, p_amount numeric, p_by_timeout boolean)
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
  update public.auction_matches set turn_seat=v_next,turn_deadline=now()+interval '10 seconds' where match_id=p_match_id;
end;
$$;

create or replace function private.auction_expire(p_match_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_board public.auction_matches; v_actor uuid; v_n int;
begin
  select * into v_board from public.auction_matches where match_id=p_match_id for update;
  if not found then return false; end if;
  if v_board.phase='lot_preview' and v_board.phase_deadline <= now() then perform private.auction_open_bidding(p_match_id); return true; end if;
  if v_board.phase='sold' and v_board.phase_deadline <= now() then
    select count(*) into v_n from public.auction_players where match_id=p_match_id;
    update public.auction_matches set current_lot=current_lot+1,opener_seat=((opener_seat+1)%v_n)::smallint where match_id=p_match_id;
    perform private.auction_advance(p_match_id); return true;
  end if;
  if v_board.phase <> 'bidding' or v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;
  select user_id into v_actor from public.auction_players where match_id=p_match_id and seat=v_board.turn_seat;
  perform private.auction_apply(p_match_id,v_actor,'pass',null,true); return true;
end;
$$;

create or replace function private.auction_turn_of(p_match_id uuid) returns public.auction_turn
language sql security definer set search_path = '' stable as $$
 select (m.match_id,m.lot_count,m.current_lot,m.turn_seat,m.opener_seat,m.turn_deadline,now(),m.phase,m.phase_deadline)::public.auction_turn
 from public.auction_matches m where m.match_id=p_match_id;
$$;

-- Same rename problem as auction_apply, and the same fix.  A drop discards the
-- grants with the function, so they are re-issued below rather than inherited.
drop function public.place_bid(uuid, int);

create function public.place_bid(p_match_id uuid, p_amount numeric) returns public.auction_turn
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); begin
 if v_user is null or (auth.jwt()->>'is_anonymous')::boolean is true then raise exception 'not_authenticated' using errcode='42501'; end if;
 perform private.auction_apply(p_match_id,v_user,'raise',p_amount,false); return private.auction_turn_of(p_match_id); end;
$$;

-- The janitor has to know about phase deadlines too.  Preview and sold leave
-- turn_deadline null and carry phase_deadline alone, so the pre-phase sweep
-- would have walked straight past an abandoned match sitting in either of them
-- and left it `playing` forever -- the one outcome this exists to prevent.
--
-- Each pass drains what it can: expiring a preview opens bidding on a deadline
-- ten seconds in the future, so the loop stops on its own within a step or two
-- rather than needing a fresh sweep per phase.
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
       and coalesce(am.turn_deadline, am.phase_deadline) < now() - interval '1 minute'
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

-- Existing boards (if a deployment lands mid-lot) remain playable.
update public.auction_matches set phase = case when turn_seat is null then 'lot_preview' else 'bidding' end,
  phase_deadline = case when turn_seat is null then now() + interval '3 seconds' else null end;

revoke all on function private.auction_open_bidding(uuid) from public, anon, authenticated;
revoke all on function private.auction_apply(uuid, uuid, text, numeric, boolean) from public, anon, authenticated;
revoke all on function public.place_bid(uuid, numeric) from public, anon;
grant execute on function public.place_bid(uuid, numeric) to authenticated;
