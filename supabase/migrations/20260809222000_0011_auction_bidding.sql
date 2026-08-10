-- Bidding, the turn timer, resolution and completion. This migration is the
-- game. Rules in docs/games/auction_team_builder.md.
--
-- Three public RPCs over one private resolver:
--
--   public.place_bid(match, increment)   -- 1 or 5
--   public.pass_lot(match)
--   public.expire_turn(match)
--           └── private.auction_apply(match, actor, action, increment, by_timeout)
--
-- Every one of them begins by taking the same single row lock on
-- auction_matches. That lock is the entire concurrency story — the game is
-- turn-based precisely so it can be — and because only ever one row is locked
-- there is no lock ordering and no deadlock path to retry.
--
-- Auto-pass runs the same code as a manual pass, and a lot resolves through the
-- same code however it got there. Two paths that both resolve a lot will drift.
--
-- THREE THINGS TO KNOW BEFORE CHANGING ANYTHING HERE.
--
-- 1. Eligibility is what keeps the board solvable. A base lot may only be bid
--    on by a player whose natural slot is still open; FLEX is live during the
--    flex round and nowhere else. Without that, an RB lot could be taken into
--    somebody's FLEX and then the RB lots run out while a player still needs
--    one. The failure is quiet — most games are fine and occasionally somebody
--    finishes with an empty slot for reasons no player can see — which is why
--    the test for it plays whole boards out instead of asserting on moves.
--
-- 2. The timer has no trustworthy owner, so it is not a subsystem. It is a
--    column. turn_deadline sits on the match row, every client renders a
--    countdown from it, and whichever client notices it has passed calls
--    expire_turn, which re-checks in server time under the lock. Client clocks
--    decide when to ask, never what is true. The obvious candidate to fire the
--    timer is the client on the clock, and that is exactly the client that
--    cannot be trusted: closing the tab is the case the timer exists for.
--
-- 3. The reveal is one line of SQL, in private.auction_resolve, and it is the
--    entire point of the product. Everything else in the auction — the private
--    pool, the two-table lot split, the private seed — exists to protect that
--    one copy from happening early.
--
-- The timer design here is expected to be lifted by the other timer-driven
-- games rather than reinvented; architecture.md points at it.

-- ------------------------------------------------------------- eligibility --

-- On a base lot: the player's slot for that exact position is unfilled. FLEX is
-- not considered. On a flex lot: the player's FLEX slot is unfilled.
--
-- Slots are derived from auction_lots rather than stored, so this cannot drift
-- from the lot rows that are the actual record of what happened.
create function private.auction_eligible(p_match_id uuid, p_user_id uuid, p_lot_seq smallint)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select case
           when l.is_flex then not exists (
             select 1 from public.auction_lots w
              where w.match_id = p_match_id
                and w.winner_id = p_user_id
                and w.slot = 'FLEX')
           else not exists (
             select 1 from public.auction_lots w
              where w.match_id = p_match_id
                and w.winner_id = p_user_id
                and w.slot = l.position)
         end
    from public.auction_lots l
   where l.match_id = p_match_id and l.seq = p_lot_seq;
$$;

-- The seats still in play on a lot: eligible, and not already passed.
create function private.auction_live_seats(p_match_id uuid, p_lot_seq smallint)
returns smallint[]
language sql
security definer
set search_path = ''
stable
as $$
  select coalesce(array_agg(ap.seat order by ap.seat), '{}'::smallint[])
    from public.auction_players ap
   where ap.match_id = p_match_id
     and private.auction_eligible(p_match_id, ap.user_id, p_lot_seq)
     and not exists (
       select 1 from public.auction_bids b
        where b.match_id = p_match_id
          and b.seq = p_lot_seq
          and b.user_id = ap.user_id
          and b.action = 'pass');
$$;

-- --------------------------------------------------------------- resolution --

-- Charge the winner, assign the slot, and reveal.
--
-- The slot assigned is the natural one on a base lot and FLEX on a flex lot,
-- which follows from the eligibility rule and needs no separate choice. There
-- is never an ambiguous assignment.
--
-- p_winner null is an unsold lot: nobody could use it. Under the scheduling
-- proof that cannot happen; it is handled rather than asserted because an
-- unsold lot is a much better failure than a stuck game.
create function private.auction_resolve(
  p_match_id uuid,
  p_seq      smallint,
  p_winner   uuid,
  p_price    int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_winner is not null then
    update public.auction_players
       set budget = budget - p_price
     where match_id = p_match_id and user_id = p_winner;
  end if;

  update public.auction_lots l
     set winner_id   = p_winner,
         price       = p_price,
         slot        = case
                         when p_winner is null then null
                         when l.is_flex        then 'FLEX'
                         else l.position
                       end,
         resolved_at = now(),
         -- THE REVEAL. Every other decision in the auction has been protecting
         -- this one copy: the pool is in `private`, the answers are in a second
         -- table so Realtime cannot replicate them early, the seed is hidden so
         -- the board cannot be replayed. This is the moment the answer becomes
         -- public, and it is the moment the lot is won.
         points      = (select a.points
                          from private.auction_answers a
                         where a.match_id = l.match_id and a.seq = l.seq)
   where l.match_id = p_match_id and l.seq = p_seq;
end;
$$;

-- Open lots until one of them actually needs somebody to act, or the board runs
-- out. Only ever looks at a lot on which nothing has been bid.
create function private.auction_advance(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board  public.auction_matches;
  v_n      int;
  v_seq    smallint;
  v_live   smallint[];
  v_seat   smallint;
  v_probe  int;
  v_scores jsonb;
begin
  select * into v_board from public.auction_matches where match_id = p_match_id;
  select count(*) into v_n from public.auction_players where match_id = p_match_id;

  loop
    v_seq := v_board.current_lot;

    -- The board is played out.
    if v_seq > v_board.lot_count then
      update public.auction_matches
         set turn_seat = null, turn_deadline = null
       where match_id = p_match_id;

      -- Everyone appears, including a player who won nothing, so the standings
      -- are the table rather than the subset that scored.
      select jsonb_object_agg(ap.user_id::text, coalesce(w.total, 0))
        into v_scores
        from public.auction_players ap
        left join (
          select winner_id, sum(points) as total
            from public.auction_lots
           where match_id = p_match_id and winner_id is not null
           group by winner_id
        ) w on w.winner_id = ap.user_id
       where ap.match_id = p_match_id;

      perform private.finish_match(p_match_id, v_scores);
      return;
    end if;

    v_live := private.auction_live_seats(p_match_id, v_seq);

    if coalesce(array_length(v_live, 1), 0) = 0 then
      perform private.auction_resolve(p_match_id, v_seq, null, null);

    elsif array_length(v_live, 1) = 1 then
      -- Exactly one eligible bidder — the final quarterback lot has this shape
      -- by construction. Awarded at $0 the moment it opens, rather than making
      -- them sit through a round of everyone else passing on a lot they could
      -- not have bid on.
      perform private.auction_resolve(
        p_match_id, v_seq,
        (select user_id from public.auction_players
          where match_id = p_match_id and seat = v_live[1]),
        0
      );

    else
      -- Somebody has to act. The right to open at $0 rotates over ELIGIBLE
      -- players, not over all seats, so an ineligible opener is skipped and the
      -- seat that is found becomes the one the next lot rotates from.
      v_seat  := v_board.opener_seat;
      v_probe := 0;
      while not (v_seat = any (v_live)) loop
        v_seat  := ((v_seat + 1) % v_n)::smallint;
        v_probe := v_probe + 1;
        if v_probe > v_n then
          raise exception 'no_eligible_opener' using errcode = 'P0001';
        end if;
      end loop;

      update public.auction_matches
         set opener_seat   = v_seat,
             turn_seat     = v_seat,
             turn_deadline = now() + interval '10 seconds'
       where match_id = p_match_id;
      return;
    end if;

    update public.auction_matches
       set current_lot = current_lot + 1,
           opener_seat = ((opener_seat + 1) % v_n)::smallint
     where match_id = p_match_id
    returning * into v_board;
  end loop;
end;
$$;

-- ------------------------------------------------------------------- a move --

-- The one resolution path. A manual pass, an auto-pass and a raise all arrive
-- here; the caller has already decided who is acting and why.
--
-- Assumes the auction_matches row is NOT yet locked — it takes the lock itself,
-- so that the three public entry points cannot each forget to.
create function private.auction_apply(
  p_match_id   uuid,
  p_actor      uuid,
  p_action     text,
  p_increment  int,
  p_by_timeout boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board    public.auction_matches;
  v_status   public.match_status;
  v_seq      smallint;
  v_seat     smallint;
  v_budget   int;
  v_price    int;
  v_high     uuid;
  v_high_st  smallint;
  v_live     smallint[];
  v_n        int;
  v_bid      smallint;
  v_next     smallint;
  v_try      smallint;
  v_i        int;
  v_winner   uuid;
begin
  select * into v_board
    from public.auction_matches
   where match_id = p_match_id
   for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  select status into v_status from public.matches where id = p_match_id;
  if v_status <> 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  select seat, budget into v_seat, v_budget
    from public.auction_players
   where match_id = p_match_id and user_id = p_actor;
  if not found then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_board.turn_seat is null or v_board.turn_seat <> v_seat then
    raise exception 'not_your_turn' using errcode = 'P0001';
  end if;

  v_seq := v_board.current_lot;

  -- Passing is final for that lot. The decision to drop out has to mean
  -- something.
  if exists (
    select 1 from public.auction_bids
     where match_id = p_match_id and seq = v_seq
       and user_id = p_actor and action = 'pass'
  ) then
    raise exception 'already_passed' using errcode = 'P0001';
  end if;

  -- The standing price and who holds it. Opening price is 0.
  select b.user_id, b.price into v_high, v_price
    from public.auction_bids b
   where b.match_id = p_match_id and b.seq = v_seq and b.action = 'raise'
   order by b.bid_seq desc
   limit 1;
  v_price := coalesce(v_price, 0);

  select coalesce(max(bid_seq), 0) + 1 into v_bid
    from public.auction_bids
   where match_id = p_match_id and seq = v_seq;

  if p_action = 'raise' then
    -- Rejected rather than clamped: a clamp would quietly turn a bid into a
    -- different bid, in a game where the number on screen is the whole point.
    if p_increment is null or p_increment not in (1, 5) then
      raise exception 'bad_increment' using errcode = 'P0001';
    end if;

    -- Only live players are ever put on the clock, so this is belt and braces —
    -- but it is the rule the whole scheduling proof rests on, so it is checked
    -- where the move is made rather than assumed from how we got here.
    if not private.auction_eligible(p_match_id, p_actor, v_seq) then
      raise exception 'not_eligible' using errcode = 'P0001';
    end if;

    -- A player who cannot afford the smallest raise can only pass. They can
    -- still win an uncontested lot, because opening is at $0 — which is why an
    -- empty wallet costs contested lots and never costs slots.
    if v_price + p_increment > v_budget then
      raise exception 'insufficient_budget' using errcode = 'P0001';
    end if;

    v_price := v_price + p_increment;
    v_high  := p_actor;

    insert into public.auction_bids (match_id, seq, bid_seq, user_id, action, price, by_timeout)
    values (p_match_id, v_seq, v_bid, p_actor, 'raise', v_price, p_by_timeout);

  elsif p_action = 'pass' then
    insert into public.auction_bids (match_id, seq, bid_seq, user_id, action, price, by_timeout)
    values (p_match_id, v_seq, v_bid, p_actor, 'pass', null, p_by_timeout);

  else
    raise exception 'bad_action' using errcode = 'P0001';
  end if;

  v_live := private.auction_live_seats(p_match_id, v_seq);
  select count(*) into v_n from public.auction_players where match_id = p_match_id;

  -- A lot resolves when one live bidder remains.
  if coalesce(array_length(v_live, 1), 0) <= 1 then
    if coalesce(array_length(v_live, 1), 0) = 1 then
      select user_id into v_winner
        from public.auction_players
       where match_id = p_match_id and seat = v_live[1];

      -- The last player standing is always the one holding the high bid: the
      -- turn never returns to the high bidder while anyone else is live, so
      -- they cannot pass out from under their own bid. If nobody raised at all,
      -- the lot goes for the $0 it opened at.
      perform private.auction_resolve(
        p_match_id, v_seq, v_winner,
        case when v_high = v_winner then v_price else 0 end
      );
    else
      perform private.auction_resolve(p_match_id, v_seq, null, null);
    end if;

    update public.auction_matches
       set current_lot = current_lot + 1,
           opener_seat = ((opener_seat + 1) % v_n)::smallint
     where match_id = p_match_id;

    perform private.auction_advance(p_match_id);
    return;
  end if;

  -- Otherwise the turn moves on, to the next live seat that is not the player
  -- already holding the high bid — nobody is ever asked to bid against
  -- themselves. There are at least two live seats and at most one of them holds
  -- the bid, so this always finds one.
  v_high_st := null;
  if v_high is not null then
    select seat into v_high_st
      from public.auction_players
     where match_id = p_match_id and user_id = v_high;
  end if;

  v_next := null;
  for v_i in 1 .. v_n loop
    v_try := ((v_seat + v_i) % v_n)::smallint;
    if v_try = any (v_live) and v_try is distinct from v_high_st then
      v_next := v_try;
      exit;
    end if;
  end loop;

  if v_next is null then
    raise exception 'no_next_bidder' using errcode = 'P0001';
  end if;

  update public.auction_matches
     set turn_seat     = v_next,
         turn_deadline = now() + interval '10 seconds'
   where match_id = p_match_id;
end;
$$;

-- Applies an auto-pass if, and only if, the deadline has really passed in
-- server time. Shared by the public RPC and by the janitor, which has no
-- auth.uid() to check.
--
-- Idempotency is structural rather than bookkept: the first successful call
-- advances the turn and sets a new deadline in the future, so every later
-- caller falls out at the check below and does nothing. Four clients racing it
-- is harmless.
create function private.auction_expire(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.auction_matches;
  v_actor uuid;
begin
  select * into v_board
    from public.auction_matches
   where match_id = p_match_id
   for update;

  if not found or v_board.turn_seat is null or v_board.turn_deadline is null then
    return false;
  end if;

  if now() < v_board.turn_deadline then
    return false;
  end if;

  select user_id into v_actor
    from public.auction_players
   where match_id = p_match_id and seat = v_board.turn_seat;
  if not found then
    return false;
  end if;

  perform private.auction_apply(p_match_id, v_actor, 'pass', null, true);
  return true;
end;
$$;

-- ------------------------------------------------------------- the write API --

create function private.auction_turn_of(p_match_id uuid)
returns public.auction_turn
language sql
security definer
set search_path = ''
stable
as $$
  select (m.match_id, m.lot_count, m.current_lot,
          m.turn_seat, m.opener_seat, m.turn_deadline, now())::public.auction_turn
    from public.auction_matches m
   where m.match_id = p_match_id;
$$;

-- What the screen loads with. Same shape as the shape every move returns, so
-- there is one thing for the client to hold.
create function public.auction_state(p_match_id uuid)
returns public.auction_turn
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  return private.auction_turn_of(p_match_id);
end;
$$;

create function public.place_bid(p_match_id uuid, p_increment int)
returns public.auction_turn
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform private.auction_apply(p_match_id, v_user, 'raise', p_increment, false);
  return private.auction_turn_of(p_match_id);
end;
$$;

create function public.pass_lot(p_match_id uuid)
returns public.auction_turn
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform private.auction_apply(p_match_id, v_user, 'pass', null, false);
  return private.auction_turn_of(p_match_id);
end;
$$;

-- Any participant may call this, which is what makes the timer live. The player
-- on the clock is the one client guaranteed to be unreliable; with everyone
-- able to fire it, the game only stalls when every client is gone.
create function public.expire_turn(p_match_id uuid)
returns public.auction_turn
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.auction_players
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  perform private.auction_expire(p_match_id);
  return private.auction_turn_of(p_match_id);
end;
$$;

-- The first lot goes through exactly the same opening as every other lot, so a
-- board whose first lot has one eligible bidder behaves the same as one whose
-- twentieth does. Replaces the placeholder opening in 0010.
create or replace function public.start_auction(p_match_id uuid)
returns public.auction_turn
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  if v_match.game <> 'auction_team_builder' then
    raise exception 'wrong_game' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.run_participants
     where run_id = v_match.run_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_match.status <> 'setup'::public.match_status then
    raise exception 'match_not_setup' using errcode = 'P0001';
  end if;

  perform private.deal_auction_board(p_match_id);

  -- Playing before advancing, because advancing can resolve lots and, on a
  -- degenerate board, finish the match outright.
  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  perform private.auction_advance(p_match_id);

  return private.auction_turn_of(p_match_id);
end;
$$;

-- --------------------------------------------------------------- the janitor --

-- A janitor, not a mechanism. On a match anybody is watching, a client fires
-- expire_turn long before this does — the minute of grace below is far longer
-- than any real client would wait. This exists so a match everyone abandoned
-- does not sit `playing` forever.
create function private.auction_sweep()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  -- Turns nobody is left to expire.
  for r in
    select am.match_id
      from public.auction_matches am
      join public.matches mt on mt.id = am.match_id
     where mt.status = 'playing'::public.match_status
       and am.turn_deadline is not null
       and am.turn_deadline < now() - interval '1 minute'
  loop
    perform private.auction_expire(r.match_id);
  end loop;

  -- Matches whose run is no longer active — a closed room, an abandoned run.
  for r in
    select mt.id
      from public.matches mt
      join public.runs rn on rn.id = mt.run_id
     where mt.status in ('setup'::public.match_status, 'playing'::public.match_status)
       and rn.status <> 'active'::public.run_status
  loop
    perform private.abandon_match(r.id);
  end loop;

  -- The seam start_run leaves open: a client that started a run and vanished
  -- before calling the game's setup. Generous, because a slow client is not an
  -- abandoned one.
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

create extension if not exists pg_cron;

select cron.schedule(
  'auction-sweep',
  '30 seconds',
  $$ select private.auction_sweep() $$
);

-- ---------------------------------------------------------------- privileges --

revoke all on function private.auction_eligible(uuid, uuid, smallint)      from public, anon, authenticated;
revoke all on function private.auction_live_seats(uuid, smallint)          from public, anon, authenticated;
revoke all on function private.auction_resolve(uuid, smallint, uuid, int)  from public, anon, authenticated;
revoke all on function private.auction_advance(uuid)                       from public, anon, authenticated;
revoke all on function private.auction_apply(uuid, uuid, text, int, boolean) from public, anon, authenticated;
revoke all on function private.auction_expire(uuid)                        from public, anon, authenticated;
revoke all on function private.auction_turn_of(uuid)                       from public, anon, authenticated;
revoke all on function private.auction_sweep()                             from public, anon, authenticated;

revoke all on function public.auction_state(uuid)      from public, anon;
revoke all on function public.place_bid(uuid, int)     from public, anon;
revoke all on function public.pass_lot(uuid)           from public, anon;
revoke all on function public.expire_turn(uuid)        from public, anon;

grant execute on function public.auction_state(uuid)   to authenticated;
grant execute on function public.place_bid(uuid, int)  to authenticated;
grant execute on function public.pass_lot(uuid)        to authenticated;
grant execute on function public.expire_turn(uuid)     to authenticated;
