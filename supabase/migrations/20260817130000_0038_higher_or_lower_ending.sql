-- The ending. A match produces a winner, or it produces sudden death, which
-- produces one anyway.
--
-- THE SHAPE. Reveal already had a job — score the question that just ended —
-- and this migration gives it a second one only at the seam where a match
-- would otherwise just stop: the reveal of the last main question decides
-- between finishing the match and opening sudden death, and the reveal of a
-- sudden-death round decides between finishing it and opening the next one.
-- Both decisions live in `expire`, exactly where the main round already
-- decided "one more question or none" — sudden death is not a second engine
-- bolted on, it is the same one asked one more question.
--
-- WHY SUDDEN DEATH IS TWO NEW PHASES AND NOT A FLAG ON THE OLD ONES. `call`
-- and `reveal` run a 12s/4s clock and accept calls from everyone still in the
-- match. Sudden death runs an 8s/4s clock and accepts calls from a strict
-- subset — the tied leaders who have not yet been eliminated. Overloading the
-- old phases with a "but only if you're admitted" exception would make every
-- future reader of `call`'s validation carry that exception in their head.
-- Two names the phase machine already distinguishes cost nothing extra.
--
-- WHY THE STANDINGS DO NOT RANK SUDDEN DEATH BY best_streak. `finish_match`
-- (0009) already turns one number per player into a placement — standard
-- competition ranking, ties sharing — and no game is allowed to invent its
-- own, so the number handed to it has to be built to rank descending into the
-- standings sudden death actually produced. best_streak keeps moving through
-- sudden death (see reveal_sudden_death_round below) so it reads like the
-- obvious source for that number — but two admitted players can be tied on it
-- while sitting at different current_streak, and an equal correct call then
-- grows only one of them. Ranking off that would let where a streak happened
-- to sit decide a placement the elimination rule never touched. The standings
-- rank admitted players by eliminated_at instead — how long they actually
-- lasted, which is what the rules say — and only fall back to correct_count
-- for whoever is never eliminated. See complete_match for the rest of it.

-- --------------------------------------------------------------- the phases --

alter table public.higher_or_lower_matches
  drop constraint higher_or_lower_matches_phase_check,
  add constraint higher_or_lower_matches_phase_check
    check (phase in (
      'board_intro', 'call', 'reveal',
      'sudden_death_call', 'sudden_death_reveal',
      'complete'
    ));

alter table public.higher_or_lower_players
  -- Admitted to the tiebreak. Set once, at the reveal that finds a tied top
  -- best streak, and never cleared — a player who was never tied never gets
  -- this and is not waited for, called on, or judged by anything below.
  add column sudden_death boolean not null default false,
  -- The question ordinal (13..17, a spare card each) a player was eliminated
  -- answering. Null means "never eliminated": still alive, or the match never
  -- entered sudden death, or the round that would have emptied the field
  -- no-op'd instead. It is the tiebreak itself — see the ranking below — so it
  -- is not reset when a match ends; there is nothing after that to reset it for.
  add column eliminated_at smallint;

-- --------------------------------------------------------- opening a round --

-- Marks the tied leaders and deals them into their first round. The band and
-- the anchor chain need nothing new here: the spares were already dealt in
-- 0032 by the same loop that dealt questions 1..12, at the same tightening
-- band, continuing the same chain — sudden death just keeps walking a ladder
-- that was already built to be walked past twelve.
create function higher_or_lower_private.enter_sudden_death(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question_count smallint;
  v_top int;
begin
  select question_count into v_question_count
    from public.higher_or_lower_matches where match_id = p_match_id;

  select max(best_streak) into v_top
    from public.higher_or_lower_players where match_id = p_match_id;

  update public.higher_or_lower_players
     set sudden_death = true
   where match_id = p_match_id and best_streak = v_top;

  perform higher_or_lower_private.open_sudden_death_round(p_match_id, (v_question_count + 1)::smallint);
end;
$$;

-- The sudden-death sibling of open_question (0037): sets the clock and the
-- presence window for one round. Shorter timer, same two facts moving
-- together — the deadline calls run to and the instant absence is measured
-- from — for the reason 0037 gives for the pair existing at all.
create function higher_or_lower_private.open_sudden_death_round(
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
         phase                = 'sudden_death_call',
         phase_deadline       = now() + interval '8 seconds',
         question_started_at  = now()
   where match_id = p_match_id;
$$;

-- ------------------------------------------------------------ settling one --

-- The sudden-death sibling of reveal_question (0037). It reveals the card,
-- records a miss for every admitted, still-alive player who said nothing, and
-- judges the round — but it does not decide what happens after. That decision
-- needs the round's clock to actually finish first, so it waits in `expire`
-- with everything else that only fires once a phase's time is up, exactly the
-- split 0037 draws between "the question is over" and "the match has moved on".
create function higher_or_lower_private.reveal_sudden_death_round(
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

  update public.higher_or_lower_cards c
     set points = a.points, revealed_at = now()
    from higher_or_lower_private.answers a
   where c.match_id = p_match_id
     and c.ordinal = p_question
     and a.match_id = c.match_id
     and a.ordinal = c.ordinal;

  -- Only the admitted and still-alive are asked, so only they can be silent.
  insert into public.higher_or_lower_calls (match_id, question, user_id, direction, timed_out)
  select p_match_id, p_question, p.user_id, null, true
    from public.higher_or_lower_players p
   where p.match_id = p_match_id
     and p.sudden_death
     and p.eliminated_at is null
     and not exists (
       select 1 from public.higher_or_lower_calls c
        where c.match_id = p_match_id and c.question = p_question and c.user_id = p.user_id
     );

  -- The counters keep moving. A sudden-death question is scored by the exact
  -- rule every other question is (0037's score_question, unmodified — it
  -- already asks calls what happened rather than assuming question <= 12), so
  -- a player's current and best streak on screen stay true through the
  -- tiebreak rather than freezing at question twelve. It reads only rows with
  -- a call for this question, which is exactly the admitted, still-alive set
  -- this round asked anything of.
  perform higher_or_lower_private.score_question(p_match_id, p_question);

  -- The elimination itself. A wrong call among the alive admitted group loses
  -- its player only when the round actually shrinks the field without
  -- emptying it — the same guard the design calls a no-op, expressed as: only
  -- write the elimination when both an alive-and-right and an alive-and-wrong
  -- exist this round.
  with judged as (
    select p.user_id,
           coalesce(
             c.direction = case when challenger.points > anchor.points then 'higher' else 'lower' end,
             false
           ) as correct
      from public.higher_or_lower_players p
      join higher_or_lower_private.answers anchor
        on anchor.match_id = p_match_id and anchor.ordinal = p_question - 1
      join higher_or_lower_private.answers challenger
        on challenger.match_id = p_match_id and challenger.ordinal = p_question
      left join public.higher_or_lower_calls c
        on c.match_id = p_match_id and c.question = p_question and c.user_id = p.user_id
     where p.match_id = p_match_id and p.sudden_death and p.eliminated_at is null
  ),
  outcome as (
    select bool_or(correct) as any_correct, bool_or(not correct) as any_wrong from judged
  )
  update public.higher_or_lower_players p
     set eliminated_at = p_question
    from judged j, outcome o
   where p.match_id = p_match_id
     and p.user_id = j.user_id
     and not j.correct
     and o.any_correct
     and o.any_wrong;

  -- Presence, judged exactly as the main round judges it (0037): over the
  -- whole question, latched rather than recomputed, on every participant —
  -- someone who is only watching still ticks on the same clock hook, so this
  -- costs the table nothing and keeps one presence rule for the whole match.
  update public.higher_or_lower_players p
     set absent = true
   where p.match_id = p_match_id
     and not p.absent
     and v_opened is not null
     and p.last_seen_at < v_opened;

  update public.higher_or_lower_matches
     set phase = 'sudden_death_reveal', phase_deadline = now() + interval '4 seconds'
   where match_id = p_match_id;
end;
$$;

-- -------------------------------------------------------------- the ending --

-- Where every path out of the match converges. Standard competition ranking
-- (0009's finish_match) needs one number per player that ranks descending into
-- the standings this game actually produced:
--
--   - Never tied for the top best streak: that best streak, unchanged. These
--     players' placements were decided at question twelve and sudden death
--     never touches them.
--   - Admitted to sudden death: a fixed 1000 plus a tiebreak, so every
--     admitted player outranks every player who was not — 1000 is more
--     margin than a best streak this deck can produce (at most seventeen
--     cards) ever closes.
--
-- The tiebreak is a dense rank over "how long did they last": eliminated_at
-- descending (later elimination beats earlier; never-eliminated beats every
-- elimination), and for the never-eliminated — a solved sudden death has
-- exactly one, an exhausted or capped one can have several — correct_count
-- descending. Two players sharing both keys get the same rank on purpose,
-- because nothing this match observed can tell them apart, and finish_match
-- turns that shared rank into the shared placement co-winners are meant to be.
--
-- Deliberately NOT each admitted player's own best_streak plus a small
-- tiebreak, tempting as that reads once score_question is live through sudden
-- death above. Two players can enter sudden death tied on best_streak while
-- sitting at different current_streak — one on the streak that made it,
-- one having broken and rebuilt one — and an equal correct call from both
-- grows only the first one's best_streak. That is a real difference between
-- them, but not one sudden death's rules make anything of, and ranking off
-- best_streak would let it decide a placement the elimination rule did not.
-- eliminated_at is the one signal that means only, and exactly, what this
-- game's rules say it means.
create function higher_or_lower_private.complete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_scores jsonb;
begin
  update public.higher_or_lower_matches
     set phase = 'complete', phase_deadline = null
   where match_id = p_match_id;

  with tiebreak as (
    select user_id,
           dense_rank() over (
             order by coalesce(eliminated_at, 32767) desc,
                      case when eliminated_at is null then correct_count else 0 end desc
           ) as sd_rank
      from public.higher_or_lower_players
     where match_id = p_match_id and sudden_death
  )
  select jsonb_object_agg(scored.user_id::text, scored.raw_score) into v_scores
    from (
      select user_id, best_streak::numeric as raw_score
        from public.higher_or_lower_players
       where match_id = p_match_id and not sudden_death
      union all
      select p.user_id, (1000::numeric - t.sd_rank) as raw_score
        from public.higher_or_lower_players p
        join tiebreak t on t.user_id = p.user_id
       where p.match_id = p_match_id
    ) scored;

  perform private.finish_match(p_match_id, coalesce(v_scores, '{}'::jsonb));
end;
$$;

-- ---------------------------------------------------------- the two doors --

-- Both doors already exist (0037); they gain the branches that carry a match
-- through its ending rather than a second pair of doors that would have to be
-- kept in step with the first.

create or replace function higher_or_lower_private.expire(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.higher_or_lower_matches;
  v_top int;
  v_tied int;
  v_alive int;
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
      -- Best streak descending, and only a tie for the top of it opens sudden
      -- death — a tie anywhere else already shares a placement and needs
      -- nothing from this migration.
      select max(best_streak) into v_top
        from public.higher_or_lower_players where match_id = p_match_id;
      select count(*) into v_tied
        from public.higher_or_lower_players where match_id = p_match_id and best_streak = v_top;

      if v_tied >= 2 then
        perform higher_or_lower_private.enter_sudden_death(p_match_id);
      else
        perform higher_or_lower_private.complete_match(p_match_id);
      end if;
    else
      perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
    end if;
  elsif v_board.phase = 'sudden_death_call' then
    perform higher_or_lower_private.reveal_sudden_death_round(p_match_id, v_board.current_question);
  elsif v_board.phase = 'sudden_death_reveal' then
    select count(*) into v_alive
      from public.higher_or_lower_players
     where match_id = p_match_id and sudden_death and eliminated_at is null;

    if v_alive <= 1 or v_board.current_question >= v_board.question_count + v_board.spare_count then
      perform higher_or_lower_private.complete_match(p_match_id);
    else
      perform higher_or_lower_private.open_sudden_death_round(p_match_id, (v_board.current_question + 1)::smallint);
    end if;
  else
    return false;
  end if;

  return true;
end;
$$;

-- Door two: the last present player, admitted-and-alive rather than everyone
-- once sudden death is live. Same validation shape as 0037's call, plus the
-- admission check and the branch on which reveal a round's last call opens.
create or replace function higher_or_lower.call(p_match_id uuid, p_direction text)
returns public.higher_or_lower_calls
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_board public.higher_or_lower_matches;
  v_player public.higher_or_lower_players;
  v_call public.higher_or_lower_calls;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_direction not in ('higher', 'lower') then
    raise exception 'invalid_direction' using errcode = 'P0001';
  end if;

  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of hm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;

  select * into v_player
    from public.higher_or_lower_players
   where match_id = p_match_id and user_id = v_user;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;

  if v_board.phase not in ('call', 'sudden_death_call') then
    raise exception 'call_not_open' using errcode = 'P0001';
  end if;
  -- Everyone in the match may call in the main round. Once sudden death is
  -- live, only the tied leaders it admitted, and only while they are still
  -- alive in it — everyone else is watching a field already settled.
  if v_board.phase = 'sudden_death_call'
     and not (v_player.sudden_death and v_player.eliminated_at is null) then
    raise exception 'not_alive_in_sudden_death' using errcode = '42501';
  end if;
  if v_board.phase_deadline is null or v_board.phase_deadline <= now() then
    raise exception 'call_deadline_passed' using errcode = 'P0001';
  end if;
  if higher_or_lower_private.has_called(p_match_id, v_board.current_question, v_user) then
    raise exception 'already_called' using errcode = 'P0001';
  end if;

  update public.higher_or_lower_players
     set last_seen_at = now(), absent = false
   where match_id = p_match_id and user_id = v_user;

  insert into public.higher_or_lower_calls (match_id, question, user_id, direction)
  values (p_match_id, v_board.current_question, v_user, p_direction)
  returning * into v_call;

  insert into public.higher_or_lower_call_statuses (match_id, question, user_id)
  values (p_match_id, v_board.current_question, v_user);

  if v_board.phase = 'sudden_death_call' then
    if not exists (
      select 1
        from public.higher_or_lower_players p
       where p.match_id = p_match_id
         and p.sudden_death
         and p.eliminated_at is null
         and not p.absent
         and not exists (
           select 1 from public.higher_or_lower_calls c
            where c.match_id = p_match_id
              and c.question = v_board.current_question
              and c.user_id = p.user_id
         )
    ) then
      perform higher_or_lower_private.reveal_sudden_death_round(p_match_id, v_board.current_question);
    end if;
  else
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
  end if;

  return v_call;
end;
$$;

-- ------------------------------------------------------------------ sweep --
-- Sudden death gets the same two grace buckets 0033 gave the main round: a
-- live call phase gets a generous grace because a real person may be mid
-- decision, and a phase with no decision in it gets a short one.
create or replace function higher_or_lower_private.sweep()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare r record;
begin
  for r in
    select hm.match_id
      from public.higher_or_lower_matches hm
      join public.matches mt on mt.id = hm.match_id
     where mt.status = 'playing'::public.match_status
       and (
         (hm.phase in ('call', 'sudden_death_call') and hm.phase_deadline < now() - interval '1 minute')
         or (hm.phase in ('board_intro', 'reveal', 'sudden_death_reveal') and hm.phase_deadline < now() - interval '2 seconds')
       )
  loop
    perform higher_or_lower_private.expire(r.match_id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------- privileges --

revoke all on function higher_or_lower_private.enter_sudden_death(uuid) from public, anon, authenticated;
revoke all on function higher_or_lower_private.open_sudden_death_round(uuid, smallint) from public, anon, authenticated;
revoke all on function higher_or_lower_private.reveal_sudden_death_round(uuid, smallint) from public, anon, authenticated;
revoke all on function higher_or_lower_private.complete_match(uuid) from public, anon, authenticated;
