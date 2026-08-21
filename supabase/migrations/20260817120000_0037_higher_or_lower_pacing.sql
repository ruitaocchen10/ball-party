-- Pacing. Three changes that are really one: the reveal transition becomes the
-- single place a question is settled, and the two things that can trigger it —
-- an expired deadline and the last present player calling — become two doors
-- into the same room.
--
-- WHY ONE ROOM. 0034 scored a call inside the call RPC, which made the reveal
-- transition a second place a streak could move. Two paths that both end a
-- streak drift: one learns about sudden death, or a scoring change, or a
-- flagged miss, and the other does not. Everything a question does — reveal the
-- card, record the people who said nothing, score, judge presence — now happens
-- in higher_or_lower_private.reveal_question and nowhere else.
--
-- It also closes a leak that 0034 left open. `higher_or_lower_players` is
-- client-readable and in the Realtime publication, so a streak that moved the
-- instant a call landed announced whether that call was right, to its owner and
-- to everyone who could already read the direction — before the number came up.
-- The concealed points in 0032 exist to stop exactly that. Scoring at the
-- reveal is what makes the beat before the number an actual beat.
--
-- WHY EARLY ADVANCE IS SYNCHRONOUS AND EXPIRY IS POLLED. They look like the
-- same event and are deliberately built differently. Expiry is a fact about the
-- clock, which no client owns, so it is re-checked under the board lock by
-- whoever asks. Early advance is a fact about a write that just happened, and
-- the transaction that made that write already holds the board lock and already
-- knows. Checking it there costs nothing; a poll would cost a round trip on the
-- path that decides typical pace, which is roughly half the ceiling.
--
-- WHY PRESENCE IS A WHOLE QUESTION. A few seconds of silence is a network
-- hiccup, and skipping somebody mid-thought over one dropped packet is worse
-- than waiting. So the unit is the question: tick anywhere inside it and you
-- are present for it, tick nowhere in it and you are latched absent at its
-- reveal. The table pays the cost of waiting for a departed player exactly
-- once, and a returning player's next tick puts them back.

-- ------------------------------------------------------------------ presence --

-- Rides on the poll that already exists rather than on a channel: the tick RPC
-- is the one thing every open client already calls, so presence costs no new
-- endpoint and no second thing to keep alive. Naming follows lobby_members
-- (0026), which stamps the same column from its own heartbeat.
--
-- A dealt player starts present. The alternative — null, meaning "never seen" —
-- would latch every seat absent at the first reveal of every match, because a
-- board is dealt before anybody has had the chance to tick.
alter table public.higher_or_lower_players
  add column last_seen_at timestamptz not null default now(),
  add column absent       boolean     not null default false;

-- When the question now ending began, which is what "no tick during it" is
-- measured against. On the board row rather than derived from phase_deadline
-- minus the call duration: the sweep and any future retune both move that
-- deadline, and a presence rule that reads a duration backwards out of it would
-- silently change meaning with them.
alter table public.higher_or_lower_matches
  add column question_started_at timestamptz;

-- A live board has a question already in flight with nobody's ticks recorded
-- against it. Opening its window now means the first reveal after this
-- migration judges presence over the part of the question that could have been
-- observed, rather than latching the whole table absent.
update public.higher_or_lower_matches hm
   set question_started_at = now()
  from public.matches mt
 where mt.id = hm.match_id
   and mt.status = 'playing'::public.match_status;

-- -------------------------------------------------------------- the timeout --

-- A miss is a call row with no direction. It could have been a separate table,
-- and that would have been the mistake: scoring would then have to ask two
-- relations what a player did, and the branch it wrote to tell them apart is
-- exactly the branch this migration exists to remove. Here the scoring
-- statement below compares a null direction against the right answer, gets
-- null, and coalesces to wrong — the same arithmetic, no special case.
--
-- `timed_out` is therefore not what scoring reads. It is what the UI reads, to
-- say "timed out" instead of "wrong", and the check keeps the two facts from
-- disagreeing.
alter table public.higher_or_lower_calls
  alter column direction drop not null,
  add column timed_out boolean not null default false,
  add constraint higher_or_lower_calls_miss_has_no_direction
    check ((direction is null) = timed_out);

-- ------------------------------------------------------------- the scoring --

-- Every participant's counters for one question, from their call row. Split out
-- from the transition below only so the transition reads as a sequence of named
-- steps; it has one caller and is not a seam.
--
-- The join is to the private answers rather than to the revealed card, so this
-- does not depend on the reveal above it having already run and cannot be
-- fooled by a card whose points were written by anything else.
create function higher_or_lower_private.score_question(
  p_match_id uuid,
  p_question smallint
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.higher_or_lower_players p
     set current_streak = case when x.correct then p.current_streak + 1 else 0 end,
         best_streak    = case when x.correct then greatest(p.best_streak, p.current_streak + 1)
                               else p.best_streak end,
         correct_count  = p.correct_count + case when x.correct then 1 else 0 end
    from (
      select c.user_id,
             -- A miss has no direction, so this comparison is null, so it is
             -- wrong. That is the whole of "a timeout runs the scoring path a
             -- wrong call runs".
             coalesce(
               c.direction = case when challenger.points > anchor.points then 'higher' else 'lower' end,
               false
             ) as correct
        from public.higher_or_lower_calls c
        join higher_or_lower_private.answers anchor
          on anchor.match_id = c.match_id and anchor.ordinal = c.question - 1
        join higher_or_lower_private.answers challenger
          on challenger.match_id = c.match_id and challenger.ordinal = c.question
       where c.match_id = p_match_id and c.question = p_question
    ) x
   where p.match_id = p_match_id and p.user_id = x.user_id;
$$;

-- --------------------------------------------------------- the transitions --

-- Open one question. The only way a question begins — from the board intro and
-- from the reveal before it — because a question's start is now two facts that
-- have to agree: the deadline the call phase runs to, and the instant presence
-- starts being measured from. Two sites setting one of those and forgetting the
-- other is how a table gets silently latched absent.
create function higher_or_lower_private.open_question(
  p_match_id uuid,
  p_question smallint
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.higher_or_lower_matches
     set current_question     = p_question,
         phase                = 'call',
         phase_deadline       = now() + interval '12 seconds',
         question_started_at  = now()
   where match_id = p_match_id;
$$;

-- Settle one question. The only way a question ends, whichever door was used.
--
-- It does not take the board lock and must not: both callers already hold it,
-- and re-taking it here would say this function is safe to call without one.
create function higher_or_lower_private.reveal_question(
  p_match_id uuid,
  p_question smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_opened timestamptz;
begin
  select question_started_at into v_opened
    from public.higher_or_lower_matches where match_id = p_match_id;

  -- The reveal itself: one number crosses from the private answers onto the
  -- client-readable card. See 0032 for why that copy is the whole mechanism.
  update public.higher_or_lower_cards c
     set points = a.points, revealed_at = now()
    from higher_or_lower_private.answers a
   where c.match_id = p_match_id
     and c.ordinal = p_question
     and a.match_id = c.match_id
     and a.ordinal = c.ordinal;

  -- Everyone who said nothing gets a row like everyone else's. Absent players
  -- included: they are still in the match, still on the scoreboard, and a
  -- question they were not there for is a question they missed.
  insert into public.higher_or_lower_calls (match_id, question, user_id, direction, timed_out)
  select p_match_id, p_question, p.user_id, null, true
    from public.higher_or_lower_players p
   where p.match_id = p_match_id
     and not exists (
       select 1 from public.higher_or_lower_calls c
        where c.match_id = p_match_id and c.question = p_question and c.user_id = p.user_id
     );

  perform higher_or_lower_private.score_question(p_match_id, p_question);

  -- Presence, judged over the question that just ended. Latching rather than
  -- recomputing: an absent player stays absent until they say otherwise, which
  -- is what makes the wait for a departed player cost one question rather than
  -- one per question.
  update public.higher_or_lower_players p
     set absent = true
   where p.match_id = p_match_id
     and not p.absent
     and v_opened is not null
     and p.last_seen_at < v_opened;

  update public.higher_or_lower_matches
     set phase = 'reveal', phase_deadline = now() + interval '4 seconds'
   where match_id = p_match_id;
end;
$$;

-- ------------------------------------------------------------ the two doors --

-- Door one: the clock. Unchanged in shape from 0033 — one expired phase per
-- call, re-checked under the board lock — except that it now hands both ends of
-- a question to the pair above rather than spelling either out itself.
create or replace function higher_or_lower_private.expire(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.higher_or_lower_matches;
  v_scores jsonb;
begin
  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of hm;

  if not found or v_board.phase_deadline is null or v_board.phase_deadline > now() then
    return false;
  end if;

  if v_board.phase = 'board_intro' then
    perform higher_or_lower_private.open_question(p_match_id, 1::smallint);
  elsif v_board.phase = 'call' then
    perform higher_or_lower_private.reveal_question(p_match_id, v_board.current_question);
  elsif v_board.phase = 'reveal' then
    if v_board.current_question >= v_board.question_count then
      update public.higher_or_lower_matches
         set phase = 'complete', phase_deadline = null
       where match_id = p_match_id;

      select jsonb_object_agg(user_id::text, 0) into v_scores
        from public.higher_or_lower_players
       where match_id = p_match_id;
      perform private.finish_match(p_match_id, coalesce(v_scores, '{}'::jsonb));
    else
      perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
    end if;
  else
    return false;
  end if;

  return true;
end;
$$;

-- Door two: the last present player. Same validation as 0034, minus the inline
-- scoring, plus a presence stamp and the early-advance check.
create or replace function higher_or_lower.call(p_match_id uuid, p_direction text)
returns public.higher_or_lower_calls
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_board public.higher_or_lower_matches;
  v_call public.higher_or_lower_calls;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_direction not in ('higher', 'lower') then
    raise exception 'invalid_direction' using errcode = 'P0001';
  end if;

  -- One match-row lock serializes both deadline validation and a player's
  -- duplicate call. The second transaction sees the first one's row only
  -- after it has committed, so no unique-violation race leaks through — and
  -- the early advance below reads a call set nobody else is still writing to.
  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of hm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (
    select 1 from public.higher_or_lower_players
     where match_id = p_match_id and user_id = v_user
  ) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_board.phase <> 'call' then raise exception 'call_not_open' using errcode = 'P0001'; end if;
  if v_board.phase_deadline is null or v_board.phase_deadline <= now() then
    raise exception 'call_deadline_passed' using errcode = 'P0001';
  end if;
  if higher_or_lower_private.has_called(p_match_id, v_board.current_question, v_user) then
    raise exception 'already_called' using errcode = 'P0001';
  end if;

  -- Calling is a stronger statement of presence than ticking, so it says the
  -- same thing. Without this a player whose ticks were all lost could call,
  -- be latched absent by the reveal a moment later, and be skipped on the next
  -- question despite having just played this one.
  update public.higher_or_lower_players
     set last_seen_at = now(), absent = false
   where match_id = p_match_id and user_id = v_user;

  insert into public.higher_or_lower_calls (match_id, question, user_id, direction)
  values (p_match_id, v_board.current_question, v_user, p_direction)
  returning * into v_call;

  insert into public.higher_or_lower_call_statuses (match_id, question, user_id)
  values (p_match_id, v_board.current_question, v_user);

  -- The early advance. Absent players are not counted, so a table whose fourth
  -- player closed their laptop still moves at the speed of the three who are
  -- there. The caller has just been marked present and has just called, so this
  -- set is never vacuously empty.
  if not exists (
    select 1
      from public.higher_or_lower_players p
     where p.match_id = p_match_id
       and not p.absent
       and not exists (
         select 1 from public.higher_or_lower_calls c
          where c.match_id = p_match_id
            and c.question = v_board.current_question
            and c.user_id = p.user_id
       )
  ) then
    perform higher_or_lower_private.reveal_question(p_match_id, v_board.current_question);
  end if;

  return v_call;
end;
$$;

-- ------------------------------------------------------------------- the tick --

-- Stamps its caller before doing anything else, so presence is recorded even on
-- the tick that goes on to end the question.
--
-- The board lock is taken first, ahead of the player row this then writes,
-- because higher_or_lower.call takes them in that order too. A tick that locked
-- its own player row and then waited for the board, while a call held the board
-- and waited to score that same player row, is a deadlock — rare, real, and
-- avoided by everyone agreeing on the order rather than by luck.
create or replace function higher_or_lower.tick(p_match_id uuid)
returns higher_or_lower.board
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform 1 from public.higher_or_lower_matches where match_id = p_match_id for update;

  update public.higher_or_lower_players
     set last_seen_at = now(), absent = false
   where match_id = p_match_id and user_id = v_user;
  if not found then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  perform higher_or_lower_private.expire(p_match_id);
  return higher_or_lower_private.board_of(p_match_id);
end;
$$;

-- ---------------------------------------------------------------- privileges --

revoke all on function higher_or_lower_private.open_question(uuid, smallint)
  from public, anon, authenticated;
revoke all on function higher_or_lower_private.score_question(uuid, smallint)
  from public, anon, authenticated;
revoke all on function higher_or_lower_private.reveal_question(uuid, smallint)
  from public, anon, authenticated;
