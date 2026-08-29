-- A best streak remains Higher or Lower's score. Total correct answers only
-- decide a tie on that score; sudden death is for the tie that remains.
--
-- `private.finish_match` takes one numeric value per player. Keep the visible
-- score's integer part as the best streak and encode total correct in the
-- thousandths, which is safely below one full streak and therefore cannot
-- overturn it. The final screen reads the game rows for its stat line, not
-- this ordering value.

create or replace function higher_or_lower_private.complete_match(p_match_id uuid)
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
      select user_id, best_streak::numeric + correct_count::numeric / 1000 as raw_score
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

create or replace function higher_or_lower_private.enter_sudden_death(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question_count smallint;
  v_top int;
  v_top_correct int;
begin
  select question_count into v_question_count
    from public.higher_or_lower_matches where match_id = p_match_id;

  select max(best_streak) into v_top
    from public.higher_or_lower_players where match_id = p_match_id;
  select max(correct_count) into v_top_correct
    from public.higher_or_lower_players
   where match_id = p_match_id and best_streak = v_top;

  update public.higher_or_lower_players
     set sudden_death = true
   where match_id = p_match_id
     and best_streak = v_top
     and correct_count = v_top_correct;

  perform higher_or_lower_private.open_sudden_death_round(p_match_id, (v_question_count + 1)::smallint);
end;
$$;

create or replace function higher_or_lower_private.expire(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.higher_or_lower_matches;
  v_top int;
  v_top_correct int;
  v_tied int;
  v_alive int;
begin
  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id and mt.status = 'playing'::public.match_status
   for update of hm;
  if not found or v_board.phase_deadline is null or v_board.phase_deadline > now() then return false; end if;

  if v_board.phase = 'board_intro' then
    perform higher_or_lower_private.open_question(p_match_id, 1::smallint);
  elsif v_board.phase = 'call' then
    perform higher_or_lower_private.reveal_question(p_match_id, v_board.current_question);
  elsif v_board.phase = 'reveal' then
    if v_board.is_solo then
      if exists (
        select 1 from public.higher_or_lower_players
         where match_id = p_match_id and current_streak = 0
      ) then
        perform higher_or_lower_private.complete_match(p_match_id);
      elsif v_board.current_question < v_board.question_count then
        perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
      elsif higher_or_lower_private.extend_board(p_match_id) then
        perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
      else
        perform higher_or_lower_private.complete_match(p_match_id);
      end if;
    elsif v_board.current_question >= v_board.question_count then
      select max(best_streak) into v_top
        from public.higher_or_lower_players where match_id = p_match_id;
      select max(correct_count) into v_top_correct
        from public.higher_or_lower_players
       where match_id = p_match_id and best_streak = v_top;
      select count(*) into v_tied
        from public.higher_or_lower_players
       where match_id = p_match_id
         and best_streak = v_top
         and correct_count = v_top_correct;

      if v_tied >= 2 then perform higher_or_lower_private.enter_sudden_death(p_match_id);
      else perform higher_or_lower_private.complete_match(p_match_id); end if;
    else
      perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
    end if;
  elsif v_board.phase = 'sudden_death_call' then
    perform higher_or_lower_private.reveal_sudden_death_round(p_match_id, v_board.current_question);
  elsif v_board.phase = 'sudden_death_reveal' then
    select count(*) into v_alive from public.higher_or_lower_players
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
