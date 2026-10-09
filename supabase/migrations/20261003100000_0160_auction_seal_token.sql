-- Seal token: the third ability from 0158's shared budget, and the only one
-- that touches the auction's core resolution loop. Turn-based ascending
-- bidding is deliberate (docs/games/auction_team_builder.md: "only one
-- player can act at any moment, so there are no race conditions, no
-- simultaneous-submit reconciliation") -- sealing a lot is precisely the
-- simultaneous-submit case that design avoided, so it gets its own phase
-- rather than being squeezed into 'bidding'.
--
-- The shape: a live, eligible player may seal the CURRENT lot before anyone
-- has bid on it (and only when at least two players are live on it --
-- sealing a lot only one person could ever win is moot). The match enters a
-- new `phase = 'sealed'` with no single turn_seat; every live player gets
-- one shot at a private amount, shared clock, first price. Resolution
-- mirrors sabotage_draft's shared-turn-clock shape (0063) more than it
-- mirrors anything already in this engine: whoever submits last resolves
-- it immediately, a missed deadline treats every non-submitter as a $0 bid,
-- and both paths funnel into the exact same resolution query so there is
-- only one place "who won, at what price" is decided.
--
-- Privacy shape: one amount-holding table scoped to its own owner (same RLS
-- pattern as 0159's scouting hints and sabotage_draft_picks before it), and
-- a sibling presence table any match member can read, so "you / waiting on
-- Tasha" is renderable without leaking what anyone actually bid.

-- ------------------------------------------------------------------- phase --

alter table public.auction_matches drop constraint auction_matches_phase_check;
alter table public.auction_matches add constraint auction_matches_phase_check
  check (phase = any (array['lot_preview', 'bidding', 'sold', 'sealed']));

-- ------------------------------------------------------------------- tables --

create table public.auction_sealed_bids (
  match_id     uuid        not null,
  seq          smallint    not null,
  user_id      uuid        not null references public.profiles (id),
  amount       int         not null check (amount >= 0),
  submitted_at timestamptz not null default now(),
  primary key (match_id, seq, user_id),
  foreign key (match_id, seq) references public.auction_lots (match_id, seq) on delete cascade
);

alter table public.auction_sealed_bids enable row level security;

-- The amount is never visible to anyone but the player who bid it -- not
-- even after the lot resolves, the same way an ascending lot's losing bids
-- stay attributed but a sealed one's losing amounts are never shown at all.
create policy auction_sealed_bids_select_own on public.auction_sealed_bids
  for select to authenticated using (user_id = auth.uid());

alter publication supabase_realtime add table public.auction_sealed_bids;

create table public.auction_sealed_bid_statuses (
  match_id  uuid     not null,
  seq       smallint not null,
  user_id   uuid     not null references public.profiles (id),
  submitted boolean  not null default false,
  primary key (match_id, seq, user_id),
  foreign key (match_id, seq) references public.auction_lots (match_id, seq) on delete cascade
);

alter table public.auction_sealed_bid_statuses enable row level security;

-- Presence, not value: any match member can see who has locked in, which is
-- what lets a client render "waiting on Tasha" without the value leaking.
create policy auction_sealed_bid_statuses_select_member on public.auction_sealed_bid_statuses
  for select to authenticated using (private.is_match_member(match_id));

alter publication supabase_realtime add table public.auction_sealed_bid_statuses;

-- Neither table has an insert/update policy -- both are written only by the
-- two RPCs below, the same shape every other auction write already has.

-- --------------------------------------------------------------- resolution --

-- Shared by the "last submitter resolves it" path inside submit_sealed_bid
-- and by auction_private.expire's deadline path, so there is exactly one
-- place that decides a sealed lot's winner and price. A player who never
-- submitted is read as a $0 bid via the coalesce below, rather than needing
-- a separate backfill step or a second code path for a missed deadline --
-- consistent with "opening is at $0" everywhere else in this engine.
-- Ties go to whoever is closest to the opener seat, stepping forward the
-- same direction every other turn-rotation in this engine already steps in
-- -- deterministic given existing state, not a fresh coin flip.
create function auction_private.resolve_sealed(p_match_id uuid, p_seq smallint)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_opener      smallint;
  v_n           int;
  v_live        smallint[];
  v_winner_seat smallint;
  v_price       int;
begin
  select opener_seat into v_opener from public.auction_matches where match_id = p_match_id;
  select count(*) into v_n from public.auction_players where match_id = p_match_id;
  v_live := auction_private.live_seats(p_match_id, p_seq);

  select ap.seat, coalesce(b.amount, 0)
    into v_winner_seat, v_price
    from public.auction_players ap
    left join public.auction_sealed_bids b
      on b.match_id = p_match_id and b.seq = p_seq and b.user_id = ap.user_id
   where ap.match_id = p_match_id and ap.seat = any(v_live)
   order by coalesce(b.amount, 0) desc, ((ap.seat - v_opener + v_n) % v_n) asc
   limit 1;

  perform auction_private.resolve(p_match_id, p_seq,
    (select user_id from public.auction_players where match_id = p_match_id and seat = v_winner_seat),
    v_price);
end;
$function$;

-- ------------------------------------------------------------------- expire --

-- Same function, new branch: a sealed phase whose shared clock has run out
-- resolves exactly like a lot every live seat has already submitted on --
-- resolve_sealed treats a missing bid as $0 either way.
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
  if v_board.phase = 'sealed' then
    if v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;
    perform auction_private.resolve_sealed(p_match_id, v_board.current_lot);
    return true;
  end if;
  if v_board.phase <> 'bidding' or v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;
  select user_id into v_actor from public.auction_players where match_id=p_match_id and seat=v_board.turn_seat;
  perform auction_private.apply(p_match_id,v_actor,'pass',null,true); return true;
end;
$function$;

-- --------------------------------------------------------------------- RPCs --

create function auction.use_seal_token(p_match_id uuid)
 returns auction.turn
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user       uuid := auth.uid();
  v_status     public.match_status;
  v_board      public.auction_matches;
  v_used_seal  boolean;
  v_live       smallint[];
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  select status into v_status from public.matches where id = p_match_id;
  if v_status is distinct from 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  select * into v_board from public.auction_matches where match_id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  if v_board.phase is distinct from 'bidding' then
    raise exception 'sealing_not_available' using errcode = 'P0001';
  end if;

  -- Sealing re-shapes a lot that has not had a single bid yet -- partway
  -- through an ascending round is a different, harder-to-explain feature.
  if exists (select 1 from public.auction_bids where match_id = p_match_id and seq = v_board.current_lot) then
    raise exception 'bidding_already_underway' using errcode = 'P0001';
  end if;

  select used_seal_token into v_used_seal
    from public.auction_players where match_id = p_match_id and user_id = v_user;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;

  if not auction_private.eligible(p_match_id, v_user, v_board.current_lot) then
    raise exception 'not_eligible' using errcode = 'P0001';
  end if;

  if v_used_seal or auction_private.tokens_used(p_match_id, v_user) >= v_board.token_count then
    raise exception 'no_seal_tokens' using errcode = 'P0001';
  end if;

  v_live := auction_private.live_seats(p_match_id, v_board.current_lot);
  if coalesce(array_length(v_live, 1), 0) < 2 then
    raise exception 'seal_needs_two_bidders' using errcode = 'P0001';
  end if;

  update public.auction_matches
     set phase = 'sealed', turn_seat = null, stuck_seat = null, free_fallback_seat = null,
         turn_deadline = now() + interval '20 seconds', phase_deadline = null
   where match_id = p_match_id;

  update public.auction_players set used_seal_token = true
   where match_id = p_match_id and user_id = v_user;

  return auction_private.turn_of(p_match_id);
end;
$function$;

create function auction.submit_sealed_bid(p_match_id uuid, p_amount numeric)
 returns auction.turn
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user   uuid := auth.uid();
  v_board  public.auction_matches;
  v_budget int;
  v_live   smallint[];
  v_all_in boolean;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  select * into v_board from public.auction_matches where match_id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  if v_board.phase is distinct from 'sealed' then
    raise exception 'sealed_bidding_not_open' using errcode = 'P0001';
  end if;

  select budget into v_budget
    from public.auction_players where match_id = p_match_id and user_id = v_user;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;

  if not auction_private.eligible(p_match_id, v_user, v_board.current_lot) then
    raise exception 'not_eligible' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.auction_sealed_bids
     where match_id = p_match_id and seq = v_board.current_lot and user_id = v_user
  ) then
    raise exception 'already_submitted' using errcode = 'P0001';
  end if;

  if p_amount is null or p_amount <> trunc(p_amount) or p_amount < 0 then
    raise exception 'bid_not_whole' using errcode = 'P0001';
  end if;
  if p_amount > v_budget then raise exception 'insufficient_budget' using errcode = 'P0001'; end if;

  insert into public.auction_sealed_bids (match_id, seq, user_id, amount)
    values (p_match_id, v_board.current_lot, v_user, p_amount::int);
  insert into public.auction_sealed_bid_statuses (match_id, seq, user_id, submitted)
    values (p_match_id, v_board.current_lot, v_user, true)
    on conflict (match_id, seq, user_id) do update set submitted = true;

  -- Resolve the instant everyone live has a bid in -- the shared clock is a
  -- backstop for the slow case, not the only way this ends.
  v_live := auction_private.live_seats(p_match_id, v_board.current_lot);
  v_all_in := not exists (
    select 1 from public.auction_players ap
     where ap.match_id = p_match_id and ap.seat = any(v_live)
       and not exists (
         select 1 from public.auction_sealed_bids b
          where b.match_id = p_match_id and b.seq = v_board.current_lot and b.user_id = ap.user_id
       )
  );
  if v_all_in then
    perform auction_private.resolve_sealed(p_match_id, v_board.current_lot);
  end if;

  return auction_private.turn_of(p_match_id);
end;
$function$;

-- ---------------------------------------------------------------- privileges --

revoke all on function auction_private.resolve_sealed(uuid, smallint) from public, anon, authenticated;
revoke all on function auction.use_seal_token(uuid) from public, anon;
grant execute on function auction.use_seal_token(uuid) to authenticated;
revoke all on function auction.submit_sealed_bid(uuid, numeric) from public, anon;
grant execute on function auction.submit_sealed_bid(uuid, numeric) to authenticated;
