-- Pass token: 1v1 (and small-table) auctions go stale because an uncontested
-- lot auto-resolves to the one remaining live bidder for $0 the instant
-- everyone else passes -- synchronously, inside the passer's own RPC call,
-- without the recipient ever being asked. See docs/games/auction_team_builder.md
-- and the design conversation this migration implements: a small per-match
-- budget (0-3) of single-use "tokens" lets a player decline a lot they'd
-- otherwise be defaulted into, a few times a game, instead of every time.
--
-- This migration ships the shared token plumbing (budget + per-ability used
-- flags, all three abilities enabled from day one even though only Pass is
-- wired up yet) plus the Pass mechanic itself. Scout and Seal land in their
-- own migrations.
--
-- The core change: both places that used to call `auction_private.resolve`
-- immediately once exactly one live, non-high bidder remains now instead
-- hand that seat a real turn (`stuck_seat`, a sibling of the existing
-- `free_fallback_seat`). Declining that turn costs a token; taking it is the
-- existing $0 claim, just explicit now instead of automatic.
--
-- A decline is NOT the same bookkeeping event a normal sale or a true
-- "nobody eligible" no-sale is, and the fuzz suite (0011/0020's stranding
-- reports) is what caught the difference. Both of those existing cases
-- consume a lot without reducing future supply below what demand needs: a
-- sale consumes one unit of supply AND fulfils one unit of demand in
-- lockstep; a "zero eligible" no-sale never represented real demand to
-- begin with. A decline is a third thing -- it destroys one unit of real
-- supply while fulfilling nobody's demand -- and the whole deal-time
-- flex-buffer floor (docs/games/auction_team_builder.md) is sized by
-- simulation on the assumption that every dealt lot either lands on a
-- roster or was never reachable by anyone. QB has zero slack by
-- construction (exactly N lots for N players), so even a single QB decline
-- would guarantee a stranded QB slot somewhere; RB/WR/TE have a floor meant
-- to absorb normal play, not a player deliberately burning supply.
--
-- So a decline redraws: it pulls one more real player of the same position
-- from the pool the board was never going to show, and appends it to the
-- end of the deck (`auction_private.redraw`, below). Total future supply of
-- that position is exactly conserved, so the deal's own math -- and its
-- simulation, not just a live inequality -- stays valid without having to
-- re-derive a global sufficiency proof for FLEX live (which is what the
-- original buffer floor already relies on simulation, not a closed form,
-- to guarantee). If the pool has nothing left to redraw (exhausted for
-- that position/era), the decline itself is refused rather than silently
-- shipping the gap -- the player still has the $0 claim as a fallback.

-- ------------------------------------------------------------------ columns --

alter table public.auction_matches
  add column token_count smallint not null default 1 check (token_count between 0 and 3),
  add column stuck_seat smallint;

alter table public.auction_players
  add column used_pass_token boolean not null default false,
  add column used_scout_token boolean not null default false,
  add column used_seal_token boolean not null default false;

-- Both tables are already RLS-visible and realtime-published to every match
-- member (0010) -- seeing a seat's remaining tokens, or that they're the
-- stuck seat, is public table state like budget or turn_seat already are.

-- -------------------------------------------------------------------- type --

alter type auction.turn add attribute stuck_seat smallint;

-- -------------------------------------------------------------------- helper --

-- How many of a player's three single-use abilities they've already spent,
-- regardless of which ones. Shared by Pass here and by Scout/Seal's own
-- migrations, so the "budget" rule lives in exactly one place.
create function auction_private.tokens_used(p_match_id uuid, p_user_id uuid)
 returns smallint
 language sql
 stable security definer
 set search_path to ''
as $function$
  select (case when used_pass_token then 1 else 0 end)
       + (case when used_scout_token then 1 else 0 end)
       + (case when used_seal_token then 1 else 0 end)
    from public.auction_players
   where match_id = p_match_id and user_id = p_user_id;
$function$;

-- -------------------------------------------------------------------- redraw --

-- Appends one more real player of `p_position` to the end of the deck, from
-- the same era and scoring mode the board was already dealt from, excluding
-- every player_id already dealt onto this match's board. Mirrors the
-- per-row draw inside `deal_board`, minus the tier filter -- a decline is
-- rare enough (at most a handful per match) that drawing across tiers
-- rather than matching the declined lot's own tier is an acceptable, much
-- simpler cost: a small skew in that one board's star:solid:deep mix, never
-- a correctness question.
create function auction_private.redraw(p_match_id uuid, p_position text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_scoring_mode text; v_season_from smallint; v_season_to smallint; v_next_seq smallint;
  v_player_id text; v_display_name text; v_season smallint; v_week smallint; v_team text; v_opponent text; v_points numeric(5,1);
begin
  select am.scoring_mode, am.season_from, am.season_to, am.lot_count + 1
    into v_scoring_mode, v_season_from, v_season_to, v_next_seq
    from public.auction_matches am where am.match_id = p_match_id;

  if v_scoring_mode = 'weekly' then
    select player_id, display_name, season, week, team, opponent, points
      into v_player_id, v_display_name, v_season, v_week, v_team, v_opponent, v_points
      from private.player_weeks
     where position = p_position and season between v_season_from and v_season_to
       and not (player_id = any(select l.player_id from public.auction_lots l where l.match_id = p_match_id))
     order by random() limit 1;
  else
    select player_id, display_name, season, null::smallint, team, null::text, points
      into v_player_id, v_display_name, v_season, v_week, v_team, v_opponent, v_points
      from private.player_seasons
     where position = p_position and season between v_season_from and v_season_to
       and not (player_id = any(select l.player_id from public.auction_lots l where l.match_id = p_match_id))
     order by random() limit 1;
  end if;

  if not found then
    raise exception 'decline_unavailable' using errcode = 'P0001';
  end if;

  insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, headshot_url)
    values (p_match_id, v_next_seq, v_player_id, v_display_name, p_position, v_season, v_week, v_team, v_opponent,
      (select h.headshot_url from private.player_headshots h where h.player_id = v_player_id));
  insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_next_seq, v_points);
  update public.auction_matches set lot_count = v_next_seq where match_id = p_match_id;
end;
$function$;

-- ----------------------------------------------------------------- turn_of --

create or replace function auction_private.turn_of(p_match_id uuid) returns auction.turn language sql security definer set search_path='' stable as $$
  select (m.match_id,m.lot_count,m.current_lot,m.turn_seat,m.opener_seat,m.turn_deadline,now(),m.phase,m.phase_deadline,m.free_fallback_seat,m.stuck_seat)::auction.turn from public.auction_matches m where m.match_id=p_match_id;
$$;

-- -------------------------------------------------------------------- resolve --

create or replace function auction_private.resolve(p_match_id uuid, p_seq smallint, p_winner uuid, p_price integer)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_position text; v_limit smallint; v_natural_won int; v_slot text;
begin
  if p_winner is not null then
    update public.auction_players set budget = budget - p_price where match_id = p_match_id and user_id = p_winner;

    select l.position, case l.position when 'QB' then am.qb_slots when 'RB' then am.rb_slots when 'WR' then am.wr_slots else am.te_slots end
      into v_position, v_limit
      from public.auction_lots l join public.auction_matches am on am.match_id = l.match_id
     where l.match_id = p_match_id and l.seq = p_seq;

    select count(*) into v_natural_won from public.auction_lots
     where match_id = p_match_id and winner_id = p_winner and slot = v_position;

    v_slot := case when v_natural_won < v_limit then v_position else 'FLEX' end;
  end if;

  update public.auction_lots l set winner_id = p_winner, price = p_price,
    slot = case when p_winner is null then null else v_slot end,
    resolved_at = now(), points = (select a.points from private.auction_answers a where a.match_id = l.match_id and a.seq = l.seq)
  where l.match_id = p_match_id and l.seq = p_seq;

  update public.auction_matches set turn_seat = null, turn_deadline = null, free_fallback_seat = null,
    stuck_seat = null, phase = 'sold', phase_deadline = now() + interval '5 seconds' where match_id = p_match_id;
end;
$function$;

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
    update public.auction_matches
       set turn_seat=v_live[1], stuck_seat=v_live[1],
           turn_deadline=now()+interval '20 seconds', phase='bidding', phase_deadline=null
     where match_id=p_match_id;
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
      update public.auction_matches set turn_seat=v_actionable[1], stuck_seat=v_actionable[1], turn_deadline=now()+interval '20 seconds' where match_id=p_match_id;
    else
      perform auction_private.resolve(p_match_id,v_seq,null,null);
    end if;
    return;
  end if;
  v_high_st:=null; if v_high is not null then select seat into v_high_st from public.auction_players where match_id=p_match_id and user_id=v_high; end if; for v_i in 1..v_n loop v_try:=((v_seat+v_i)%v_n)::smallint; if v_try=any(v_actionable) and v_try is distinct from v_high_st then v_next:=v_try; exit; end if; end loop;
  if v_next is null then raise exception 'no_next_bidder' using errcode='P0001'; end if; update public.auction_matches set turn_seat=v_next,turn_deadline=now()+interval '20 seconds' where match_id=p_match_id;
end;
$$;

-- -------------------------------------------------------------- deal_board --

-- `create or replace` only replaces a function with the SAME argument
-- signature. Adding a trailing p_token_count parameter makes this a distinct
-- overload rather than a replacement, which leaves the old 6-arg signature
-- resolvable too -- and ambiguous, the moment a caller (including every
-- existing `tests.deal` helper) invokes it with exactly the old argument
-- count. The old signature has to go first.
drop function if exists auction_private.deal_board(uuid, double precision, text, text, smallint, smallint);

create or replace function auction_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null,
  p_scoring_mode text default 'weekly',
  p_roster_preset text default 'standard',
  p_season_from smallint default null,
  p_season_to smallint default null,
  p_token_count smallint default null
)
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
  v_te_slots smallint; v_flex_slots smallint; v_purse int; v_token_count smallint;
  v_from smallint; v_to smallint;
  v_flex_buffer int; v_buf_rb int; v_buf_wr int; v_buf_te int; v_bump text[];
begin
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  v_token_count := coalesce(p_token_count, 1);
  if v_token_count < 0 or v_token_count > 3 then
    raise exception 'invalid_token_count' using errcode = 'P0001';
  end if;
  case p_roster_preset
    when 'standard' then v_qb_slots := 1; v_rb_slots := 1; v_wr_slots := 1; v_te_slots := 1; v_flex_slots := 1; v_purse := 25;
    when 'full' then v_qb_slots := 1; v_rb_slots := 2; v_wr_slots := 2; v_te_slots := 1; v_flex_slots := 1; v_purse := 35;
    when 'deep' then v_qb_slots := 2; v_rb_slots := 2; v_wr_slots := 3; v_te_slots := 1; v_flex_slots := 2; v_purse := 50;
    else raise exception 'invalid_roster_preset' using errcode = 'P0001';
  end case;
  select r.season_from, r.season_to into v_from, v_to
    from auction_private.resolve_season_range(p_season_from, p_season_to) r;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  insert into public.auction_players (match_id, user_id, seat, budget)
    select p_match_id, rp.user_id, rp.seat, v_purse from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id where m.id = p_match_id;
  select count(*) into v_n from public.auction_players where match_id = p_match_id;
  if v_n < 2 then raise exception 'too_few_players' using errcode = 'P0001'; end if;

  v_flex_buffer := v_n * v_flex_slots;
  v_buf_rb := v_flex_buffer / 3; v_buf_wr := v_flex_buffer / 3; v_buf_te := v_flex_buffer / 3;
  select array_agg(p order by random()) into v_bump from unnest(array['RB', 'WR', 'TE']) p;
  for v_i in 1 .. (v_flex_buffer % 3) loop
    case v_bump[v_i]
      when 'RB' then v_buf_rb := v_buf_rb + 1;
      when 'WR' then v_buf_wr := v_buf_wr + 1;
      else v_buf_te := v_buf_te + 1;
    end case;
  end loop;
  if v_flex_slots > 0 then
    v_buf_rb := greatest(v_buf_rb, 2);
    v_buf_wr := greatest(v_buf_wr, 2);
    v_buf_te := greatest(v_buf_te, 2);
  end if;

  v_total := v_n * v_qb_slots + v_n * v_rb_slots + v_buf_rb + v_n * v_wr_slots + v_buf_wr + v_n * v_te_slots + v_buf_te;
  v_star := (7 * v_total) / 20; v_solid := (8 * v_total) / 20; v_deep := (5 * v_total) / 20;
  select array_agg(t order by rem desc, ord) into v_order from
    (values ('star', (7 * v_total) % 20, 1), ('solid', (8 * v_total) % 20, 2), ('deep', (5 * v_total) % 20, 3)) r(t, rem, ord);
  for v_i in 1 .. (v_total - v_star - v_solid - v_deep) loop
    if v_order[v_i] = 'star' then v_star := v_star + 1; elsif v_order[v_i] = 'solid' then v_solid := v_solid + 1; else v_deep := v_deep + 1; end if;
  end loop;
  select array_agg(position order by random()) into v_slots from (
    select position from unnest(array['QB','RB','WR','TE']) positions(position),
      generate_series(1,
        v_n * (case position when 'QB' then v_qb_slots when 'RB' then v_rb_slots when 'WR' then v_wr_slots else v_te_slots end)
        + (case position when 'RB' then v_buf_rb when 'WR' then v_buf_wr when 'TE' then v_buf_te else 0 end))
  ) base;
  select array_agg(t order by random()) into v_tiers from (
    select 'star' t from generate_series(1, v_star) union all select 'solid' from generate_series(1, v_solid) union all select 'deep' from generate_series(1, v_deep)
  ) tokens;
  for v_i in 1 .. v_total loop
    if p_scoring_mode = 'weekly' then
      select player_id, display_name, position, season, week, team, opponent, points into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_weeks where position = v_slots[v_i] and tier = v_tiers[v_i]
          and season between v_from and v_to and not (player_id = any(v_used)) order by random() limit 1;
    else
      select player_id, display_name, position, season, null::smallint, team, null::text, points into v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent, v_points
        from private.player_seasons where position = v_slots[v_i] and tier = v_tiers[v_i]
          and season between v_from and v_to and not (player_id = any(v_used)) order by random() limit 1;
    end if;
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_player_id;
    insert into public.auction_lots (match_id, seq, player_id, display_name, position, season, week, team, opponent, headshot_url)
      values (p_match_id, v_i, v_player_id, v_display_name, v_position, v_season, v_week, v_team, v_opponent,
        (select h.headshot_url from private.player_headshots h where h.player_id = v_player_id));
    insert into private.auction_answers (match_id, seq, points) values (p_match_id, v_i, v_points);
  end loop;
  insert into public.auction_matches (match_id, lot_count, current_lot, opener_seat, scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, season_from, season_to, token_count)
    values (p_match_id, v_total, 1, 0, p_scoring_mode, p_roster_preset, v_qb_slots, v_rb_slots, v_wr_slots, v_te_slots, v_flex_slots, v_purse, v_from, v_to, v_token_count);
  insert into private.auction_boards (match_id, seed) values (p_match_id, v_seed);
end;
$function$;

-- ----------------------------------------------------------------- auction.start --

-- Same reasoning as deal_board above: the old 5-arg signature has to be
-- dropped explicitly, or it coexists with the new 6-arg one as an ambiguous
-- overload for any caller that omits p_token_count.
drop function if exists auction.start(uuid, text, text, smallint, smallint);

create or replace function auction.start(
  p_match_id uuid,
  p_scoring_mode text,
  p_roster_preset text,
  p_season_from smallint default null,
  p_season_to smallint default null,
  p_token_count smallint default null
)
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
  if p_token_count is not null and (p_token_count < 0 or p_token_count > 3) then raise exception 'invalid_token_count' using errcode = 'P0001'; end if;
  perform auction_private.resolve_season_range(p_season_from, p_season_to);
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform auction_private.deal_board(p_match_id, null, p_scoring_mode, p_roster_preset, p_season_from, p_season_to, p_token_count);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform auction_private.advance(p_match_id); return auction_private.turn_of(p_match_id);
end;
$function$;

-- ---------------------------------------------------------------- privileges --

-- 0029 locks every auction_private function down individually, by exact
-- signature, rather than relying on the schema-level revoke alone (defense
-- in depth: PostgreSQL grants EXECUTE to PUBLIC by default on a newly
-- created function, independent of schema USAGE). `create or replace` only
-- carries a function's existing grants forward when the signature is
-- unchanged -- deal_board's new trailing parameter and redraw/tokens_used
-- being brand new both mean fresh objects with the default (public)
-- privileges, so they need the same explicit lockdown, not an inherited one.
revoke all on function auction_private.deal_board(uuid, double precision, text, text, smallint, smallint, smallint) from public, anon, authenticated;
revoke all on function auction_private.tokens_used(uuid, uuid) from public, anon, authenticated;
revoke all on function auction_private.redraw(uuid, text) from public, anon, authenticated;

-- Same reasoning for auction.start's new signature: 0029's revoke-then-grant
-- pair named the old 5-arg signature specifically, which does not carry
-- forward to this 6-arg one.
revoke all on function auction.start(uuid, text, text, smallint, smallint, smallint) from public, anon;
grant execute on function auction.start(uuid, text, text, smallint, smallint, smallint) to authenticated;
