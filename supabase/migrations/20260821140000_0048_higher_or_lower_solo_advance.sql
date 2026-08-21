-- Fixes solo Higher or Lower getting stuck after question one (issue #33
-- follow-up).
--
-- 0046 dealt the solo board's fixed ladder up front — ordinals 0..12, an
-- anchor plus the twelve questions — and left the spares beyond it for
-- `extend_board` to append lazily. But `expire`'s solo branch called
-- `extend_board` unconditionally on every reveal, not only once the ladder
-- ran out. `deal_next_card` inserts unconditionally on `(match_id, ordinal)`,
-- which is a primary key (0032), so a correct call anywhere from question one
-- through eleven tried to re-deal an ordinal that already held its pre-dealt
-- card, raised a duplicate-key violation, and rolled the whole `expire` call
-- back — leaving the match sitting in `reveal` with an expired deadline
-- forever. The one path that ever exercised this branch cleanly was question
-- twelve, exactly where 0046's own test happens to sit, so it stayed unnoticed
-- until a solo player got the first question right.
--
-- The fix mirrors the group branch immediately below it: extend only past the
-- pre-dealt ladder (`current_question >= question_count`); before that, the
-- next card already exists, so this only ever needs to open it.

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
        -- Still inside the ladder 0046 pre-dealt: the next ordinal already
        -- has a card, so extending here would re-deal it and violate the
        -- primary key.
        perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
      elsif higher_or_lower_private.extend_board(p_match_id) then
        perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
      else
        perform higher_or_lower_private.complete_match(p_match_id);
      end if;
    elsif v_board.current_question >= v_board.question_count then
      select max(best_streak) into v_top from public.higher_or_lower_players where match_id = p_match_id;
      select count(*) into v_tied from public.higher_or_lower_players where match_id = p_match_id and best_streak = v_top;
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
