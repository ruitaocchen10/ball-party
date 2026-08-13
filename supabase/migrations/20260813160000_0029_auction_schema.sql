-- The auction moves out of `public` and `private` into its own pair of schemas.
--
-- `public` was becoming a junk drawer. Every game wants a function called
-- `state` and a function called `place_bid`, and with everything in one schema
-- the only way to keep them apart is to prefix every name with the game it
-- belongs to. Postgres already has the module system for this, so the auction
-- gets two schemas rather than a naming convention:
--
--   auction          the write API a client may call. Exposed via PostgREST,
--                    so it holds nothing that isn't meant to be reachable.
--   auction_private   the rules engine. Not in the exposed schema list, no
--                    usage granted to anon or authenticated — the same shape
--                    `private` has had since 0004, scoped to one game.
--
-- The prefixes come off on the way across: `private.auction_turn_of` reads
-- better as `auction_private.turn_of` and the schema already said "auction".
--
-- What deliberately does NOT move: the `auction_*` tables in `public` (they are
-- client-readable through RLS and sit in the Realtime publication) and the
-- hidden-state tables in `private` (`auction_answers`, `auction_boards`).
-- Relocating those touches replication membership and the policies the 0010
-- leak test asserts on, which is a change worth making on its own.
--
-- `expire_turn` comes along rather than staying behind as a platform function.
-- Per-action deadlines are a runtime concern in the architecture doc, but this
-- implementation is entirely auction — it returns `auction_turn` and reads
-- `auction_players`. A generic dispatcher can be reintroduced at the contract
-- layer when a second game needs one; inventing it now with one caller would be
-- guessing at its shape.
--
-- `public.choose_post_game` stays in `public` and is recreated only to follow
-- the renames. Orchestration is allowed to know about games — that is its job.
-- The dependency the architecture doc forbids runs the other way.

-- ------------------------------------------------------------------- schemas --

create schema if not exists auction;
create schema if not exists auction_private;

-- Mirrors 0004: the engine is unreachable because the schema is, not merely
-- because no endpoint happens to point at it.
revoke all on schema auction_private from public, anon, authenticated;

-- No RLS policy calls into the engine, so unlike `private` in 0004 there is no
-- reason to grant `authenticated` usage here.

revoke all on schema auction from public;
grant usage on schema auction to anon, authenticated, service_role;

-- ---------------------------------------------------------------- the turn type --

alter type public.auction_turn set schema auction;
alter type auction.auction_turn rename to turn;

-- ------------------------------------------------------------------ functions --

-- private.auction_eligible  ->  auction_private.eligible
CREATE OR REPLACE FUNCTION auction_private.eligible(p_match_id uuid, p_user_id uuid, p_lot_seq smallint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select count(w.*) < case when l.is_flex then am.flex_slots else
    case l.position when 'QB' then am.qb_slots when 'RB' then am.rb_slots
                    when 'WR' then am.wr_slots else am.te_slots end end
    from public.auction_lots l
    join public.auction_matches am on am.match_id = l.match_id
    left join public.auction_lots w
      on w.match_id = p_match_id and w.winner_id = p_user_id
     and w.slot = case when l.is_flex then 'FLEX' else l.position end
   where l.match_id = p_match_id and l.seq = p_lot_seq
   group by l.is_flex, l.position, am.qb_slots, am.rb_slots, am.wr_slots, am.te_slots, am.flex_slots;
$function$
;

-- private.auction_live_seats  ->  auction_private.live_seats
CREATE OR REPLACE FUNCTION auction_private.live_seats(p_match_id uuid, p_lot_seq smallint)
 RETURNS smallint[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(ap.seat order by ap.seat), '{}'::smallint[])
    from public.auction_players ap
   where ap.match_id = p_match_id
     and auction_private.eligible(p_match_id, ap.user_id, p_lot_seq)
     and not exists (
       select 1 from public.auction_bids b
        where b.match_id = p_match_id
          and b.seq = p_lot_seq
          and b.user_id = ap.user_id
          and b.action = 'pass');
$function$
;

-- private.auction_turn_of  ->  auction_private.turn_of
CREATE OR REPLACE FUNCTION auction_private.turn_of(p_match_id uuid)
 RETURNS auction.turn
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select (m.match_id,m.lot_count,m.current_lot,m.turn_seat,m.opener_seat,m.turn_deadline,now(),m.phase,m.phase_deadline)::auction.turn
 from public.auction_matches m where m.match_id=p_match_id;
$function$
;

-- private.auction_resolve  ->  auction_private.resolve
CREATE OR REPLACE FUNCTION auction_private.resolve(p_match_id uuid, p_seq smallint, p_winner uuid, p_price integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.auction_open_bidding  ->  auction_private.open_bidding
CREATE OR REPLACE FUNCTION auction_private.open_bidding(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_board public.auction_matches;
  v_live smallint[];
  v_n int;
  v_seat smallint;
  v_probe int := 0;
begin
  select * into v_board from public.auction_matches where match_id = p_match_id for update;
  if not found or v_board.phase <> 'lot_preview' then return; end if;
  v_live := auction_private.live_seats(p_match_id, v_board.current_lot);
  select count(*) into v_n from public.auction_players where match_id = p_match_id;
  if coalesce(array_length(v_live, 1), 0) = 1 then
    perform auction_private.resolve(p_match_id, v_board.current_lot,
      (select user_id from public.auction_players where match_id = p_match_id and seat = v_live[1]), 0);
    return;
  elsif coalesce(array_length(v_live, 1), 0) = 0 then
    perform auction_private.resolve(p_match_id, v_board.current_lot, null, null);
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
$function$
;

-- private.auction_advance  ->  auction_private.advance
CREATE OR REPLACE FUNCTION auction_private.advance(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.auction_apply  ->  auction_private.apply
CREATE OR REPLACE FUNCTION auction_private.apply(p_match_id uuid, p_actor uuid, p_action text, p_amount numeric, p_by_timeout boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    if not auction_private.eligible(p_match_id,p_actor,v_seq) then raise exception 'not_eligible' using errcode='P0001'; end if;
    v_price:=p_amount::int; v_high:=p_actor;
    insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic)
      values (p_match_id,v_seq,v_bid,p_actor,'raise',v_price,p_by_timeout,now(),false);
  elsif p_action='pass' then
    insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic)
      values (p_match_id,v_seq,v_bid,p_actor,'pass',null,p_by_timeout,now(),false);
  else raise exception 'bad_action' using errcode='P0001'; end if;

  v_live:=auction_private.live_seats(p_match_id,v_seq);
  if v_high is not null then
    insert into public.auction_bids (match_id,seq,bid_seq,user_id,action,price,by_timeout,created_at,automatic)
    select p_match_id, v_seq, v_bid + row_number() over (order by ap.seat), ap.user_id,
           'pass', null, false, now(), true
      from public.auction_players ap
     where ap.match_id = p_match_id
       and ap.seat = any(v_live)
       and ap.user_id <> v_high
       and ap.budget <= v_price;
    v_live:=auction_private.live_seats(p_match_id,v_seq);
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
      perform auction_private.resolve(p_match_id,v_seq,v_high,v_price);
    elsif coalesce(array_length(v_actionable,1),0)=1 then
      select user_id into v_winner from public.auction_players where match_id=p_match_id and seat=v_actionable[1];
      perform auction_private.resolve(p_match_id,v_seq,v_winner,0);
    else
      perform auction_private.resolve(p_match_id,v_seq,null,null);
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
$function$
;

-- private.auction_expire  ->  auction_private.expire
CREATE OR REPLACE FUNCTION auction_private.expire(p_match_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_board public.auction_matches; v_actor uuid; v_n int;
begin
  select * into v_board from public.auction_matches where match_id=p_match_id for update;
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

-- private.auction_sweep  ->  auction_private.sweep
CREATE OR REPLACE FUNCTION auction_private.sweep()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      exit when not auction_private.expire(r.match_id);
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
$function$
;

-- private.deal_auction_board  ->  auction_private.deal_board
CREATE OR REPLACE FUNCTION auction_private.deal_board(p_match_id uuid, p_seed double precision DEFAULT NULL::double precision, p_scoring_mode text DEFAULT 'weekly'::text, p_roster_preset text DEFAULT 'standard'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_seed double precision := coalesce(p_seed, random()); v_n int; v_total int;
  v_star int; v_solid int; v_deep int; v_order text[]; v_slots text[]; v_tiers text[];
  v_used text[] := '{}'; v_player_id text; v_display_name text; v_position text;
  v_season smallint; v_week smallint; v_team text; v_opponent text; v_points numeric(5,1);
  v_i int; v_qb_slots smallint; v_rb_slots smallint; v_wr_slots smallint;
  v_te_slots smallint; v_flex_slots smallint; v_purse int;
begin
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  case p_roster_preset
    when 'standard' then v_qb_slots := 1; v_rb_slots := 1; v_wr_slots := 1; v_te_slots := 1; v_flex_slots := 1; v_purse := 25;
    when 'full' then v_qb_slots := 1; v_rb_slots := 2; v_wr_slots := 2; v_te_slots := 1; v_flex_slots := 1; v_purse := 35;
    when 'deep' then v_qb_slots := 2; v_rb_slots := 2; v_wr_slots := 3; v_te_slots := 1; v_flex_slots := 2; v_purse := 50;
    else raise exception 'invalid_roster_preset' using errcode = 'P0001';
  end case;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  insert into public.auction_players (match_id, user_id, seat, budget)
    select p_match_id, rp.user_id, rp.seat, v_purse from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id where m.id = p_match_id;
  select count(*) into v_n from public.auction_players where match_id = p_match_id;
  if v_n < 2 then raise exception 'too_few_players' using errcode = 'P0001'; end if;
  v_total := (v_qb_slots + v_rb_slots + v_wr_slots + v_te_slots + v_flex_slots) * v_n;
  v_star := (7 * v_total) / 20; v_solid := (8 * v_total) / 20; v_deep := (5 * v_total) / 20;
  select array_agg(t order by rem desc, ord) into v_order from
    (values ('star', (7 * v_total) % 20, 1), ('solid', (8 * v_total) % 20, 2), ('deep', (5 * v_total) % 20, 3)) r(t, rem, ord);
  for v_i in 1 .. (v_total - v_star - v_solid - v_deep) loop
    if v_order[v_i] = 'star' then v_star := v_star + 1; elsif v_order[v_i] = 'solid' then v_solid := v_solid + 1; else v_deep := v_deep + 1; end if;
  end loop;
  select array_agg(position order by random()) into v_slots from (
    select position from unnest(array['QB','RB','WR','TE']) positions(position),
      generate_series(1, v_n * case position when 'QB' then v_qb_slots when 'RB' then v_rb_slots when 'WR' then v_wr_slots else v_te_slots end)
  ) base;
  v_slots := v_slots || (select array_agg((array['RB','WR','TE'])[1 + floor(random() * 3)::int]) from generate_series(1, v_n * v_flex_slots));
  select array_agg(t order by random()) into v_tiers from (
    select 'star' t from generate_series(1, v_star) union all select 'solid' from generate_series(1, v_solid) union all select 'deep' from generate_series(1, v_deep)
  ) tokens;
  for v_i in 1 .. v_total loop
    if p_scoring_mode = 'weekly' then
      select player_id, display_name, position, season, week, team, opponent, points into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_weeks where position = v_slots[v_i] and tier = v_tiers[v_i] and not (player_id = any(v_used)) order by random() limit 1;
    else
      select player_id, display_name, position, season, null::smallint, team, null::text, points into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_seasons where position = v_slots[v_i] and tier = v_tiers[v_i] and not (player_id = any(v_used)) order by random() limit 1;
    end if;
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_player_id;
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, is_flex, headshot_url)
      values (p_match_id, v_i, v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_i > v_total - (v_n * v_flex_slots),
        -- Left join in spirit, as in 0013: a player the headshot table has not
        -- caught up with still deals a perfectly good lot, with an empty band.
        (select h.headshot_url from private.player_headshots h where h.player_id = v_player_id));
    insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_i, v_points);
  end loop;
  insert into public.auction_matches (match_id, lot_count, current_lot, opener_seat, scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse)
    values (p_match_id, v_total, 1, 0, p_scoring_mode, p_roster_preset, v_qb_slots, v_rb_slots, v_wr_slots, v_te_slots, v_flex_slots, v_purse);
  insert into private.auction_boards (match_id, seed) values (p_match_id, v_seed);
end;
$function$
;

-- public.auction_state  ->  auction.state
CREATE OR REPLACE FUNCTION auction.state(p_match_id uuid)
 RETURNS auction.turn
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  return auction_private.turn_of(p_match_id);
end;
$function$
;

-- public.start_auction  ->  auction.start
CREATE OR REPLACE FUNCTION auction.start(p_match_id uuid, p_scoring_mode text, p_roster_preset text)
 RETURNS auction.turn
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  if p_roster_preset is distinct from 'standard' and p_roster_preset is distinct from 'full' and p_roster_preset is distinct from 'deep' then raise exception 'invalid_roster_preset' using errcode = 'P0001'; end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform auction_private.deal_board(p_match_id, null, p_scoring_mode, p_roster_preset);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform auction_private.advance(p_match_id); return auction_private.turn_of(p_match_id);
end;
$function$
;

-- public.place_bid  ->  auction.place_bid
CREATE OR REPLACE FUNCTION auction.place_bid(p_match_id uuid, p_amount numeric)
 RETURNS auction.turn
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  perform auction_private.apply(p_match_id, v_user, 'raise', p_amount, false);
  return auction_private.turn_of(p_match_id);
end;
$function$
;

-- public.pass_lot  ->  auction.pass_lot
CREATE OR REPLACE FUNCTION auction.pass_lot(p_match_id uuid)
 RETURNS auction.turn
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  perform auction_private.apply(p_match_id, v_user, 'pass', null, false);
  return auction_private.turn_of(p_match_id);
end;
$function$
;

-- public.expire_turn  ->  auction.expire_turn
CREATE OR REPLACE FUNCTION auction.expire_turn(p_match_id uuid)
 RETURNS auction.turn
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not exists (select 1 from public.auction_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  perform auction_private.expire(p_match_id);
  return auction_private.turn_of(p_match_id);
end;
$function$
;

-- public.choose_post_game  ->  stays put; recreated to follow the renames
CREATE OR REPLACE FUNCTION public.choose_post_game(p_match_id uuid, p_choice public.post_game_choice)
 RETURNS public.post_game_actions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_match public.matches;
  v_run public.runs;
  v_lobby public.lobbies;
  v_format public.auction_matches;
  v_next_run public.runs;
  v_next_match public.matches;
  v_action public.post_game_actions;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.status <> 'complete'::public.match_status then
    raise exception 'match_not_complete' using errcode = 'P0001';
  end if;

  select * into v_run from public.runs where id = v_match.run_id;
  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
  if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.lobby_members
     where lobby_id = v_lobby.id and user_id = v_user and left_at is null
  ) then raise exception 'not_a_member' using errcode = '42501'; end if;

  if exists (select 1 from public.post_game_actions where match_id = p_match_id) then
    raise exception 'post_game_choice_already_made' using errcode = 'P0001';
  end if;

  if p_choice = 'replay'::public.post_game_choice then
    if v_match.game <> 'auction_team_builder' then
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

    select * into v_format from public.auction_matches where match_id = p_match_id;
    if not found or v_format.scoring_mode is null or v_format.roster_preset is null then
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

    insert into public.runs (lobby_id, mode)
    values (v_lobby.id, 'arcade'::public.run_mode)
    returning * into v_next_run;

    insert into public.run_participants (run_id, user_id, seat)
    select v_next_run.id, user_id, seat
      from public.run_participants
     where run_id = v_run.id;

    insert into public.matches (run_id, game, seq, status)
    values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status)
    returning * into v_next_match;

    perform auction_private.deal_board(
      v_next_match.id, null, v_format.scoring_mode, v_format.roster_preset
    );
    update public.matches
       set status = 'playing'::public.match_status, started_at = now()
     where id = v_next_match.id;
    perform auction_private.advance(v_next_match.id);

    insert into public.post_game_actions (match_id, choice, next_match_id)
    values (p_match_id, p_choice, v_next_match.id)
    returning * into v_action;
  else
    insert into public.post_game_actions (match_id, choice)
    values (p_match_id, p_choice)
    returning * into v_action;
  end if;

  return v_action;
end;
$function$
;

-- --------------------------------------------------------- the old definitions --

drop function if exists public.start_auction(uuid, text, text);
drop function if exists public.place_bid(uuid, numeric);
drop function if exists public.pass_lot(uuid);
drop function if exists public.expire_turn(uuid);
drop function if exists public.auction_state(uuid);

drop function if exists private.deal_auction_board(uuid, double precision, text, text);
drop function if exists private.auction_sweep();
drop function if exists private.auction_expire(uuid);
drop function if exists private.auction_apply(uuid, uuid, text, numeric, boolean);
drop function if exists private.auction_advance(uuid);
drop function if exists private.auction_open_bidding(uuid);
drop function if exists private.auction_resolve(uuid, smallint, uuid, integer);
drop function if exists private.auction_turn_of(uuid);
drop function if exists private.auction_live_seats(uuid, smallint);
drop function if exists private.auction_eligible(uuid, uuid, smallint);

-- ------------------------------------------------------------------- the sweep --

-- pg_cron keys jobs by name, so this rewrites the registration from 0011 in
-- place. Without it the backstop keeps pointing at a function that no longer
-- exists and fails every 30 seconds where nobody is looking.
select cron.schedule(
  'auction-sweep',
  '30 seconds',
  $$ select auction_private.sweep() $$
);

-- ------------------------------------------------------------------ privileges --

revoke all on function auction_private.eligible(uuid, uuid, smallint)              from public, anon, authenticated;
revoke all on function auction_private.live_seats(uuid, smallint)                  from public, anon, authenticated;
revoke all on function auction_private.turn_of(uuid)                               from public, anon, authenticated;
revoke all on function auction_private.resolve(uuid, smallint, uuid, integer)      from public, anon, authenticated;
revoke all on function auction_private.open_bidding(uuid)                          from public, anon, authenticated;
revoke all on function auction_private.advance(uuid)                               from public, anon, authenticated;
revoke all on function auction_private.apply(uuid, uuid, text, numeric, boolean)   from public, anon, authenticated;
revoke all on function auction_private.expire(uuid)                                from public, anon, authenticated;
revoke all on function auction_private.sweep()                                     from public, anon, authenticated;
revoke all on function auction_private.deal_board(uuid, double precision, text, text) from public, anon, authenticated;

revoke all on function auction.start(uuid, text, text) from public, anon;
revoke all on function auction.place_bid(uuid, numeric) from public, anon;
revoke all on function auction.pass_lot(uuid)           from public, anon;
revoke all on function auction.expire_turn(uuid)        from public, anon;
revoke all on function auction.state(uuid)              from public, anon;

grant execute on function auction.start(uuid, text, text) to authenticated;
grant execute on function auction.place_bid(uuid, numeric) to authenticated;
grant execute on function auction.pass_lot(uuid)           to authenticated;
grant execute on function auction.expire_turn(uuid)        to authenticated;
grant execute on function auction.state(uuid)              to authenticated;
