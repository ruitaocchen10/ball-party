-- Per-game resolution for multi-game Picks posts.
--
-- Until now a post resolved as a whole: grade_due_game_picks (0096/0100/0111)
-- skipped a post unless every one of its slots' games was final, so a weekly
-- slate showed nothing — not even the Thursday night result — until Monday
-- night's game ended. Every slot on a weekly post already carries its own
-- source_game_id (0097) and is graded independently inside do_resolve, so the
-- post-level gate was the only thing holding a finished game's answer back.
--
-- Now each slot is graded and revealed on its own as its game goes final, and
-- the post flips to 'resolved' when its last slot is graded. What "resolved"
-- gates is unchanged: prompt_posts.status = 'resolved' is still what the
-- profile stats (0107/0108/0109) and the client's post-level total wait on, so
-- the points_earned this now writes to a still-open post never reach a
-- ranking or a "+N" total until the whole post is done.
--
-- Split into three functions, all prompts_private-only like do_resolve:
--   grade_slot        validate + record one slot's answer, reveal it, score it
--   do_resolve_slot   guard + grade_slot + close the post if that was the last
--   do_resolve        guard + grade_slot for every slot + close (admin path)
-- grade_slot exists separately so do_resolve's loop can't close the post
-- part-way through: a post whose other slots were already auto-graded would
-- otherwise look "complete" after an earlier iteration and refuse the rest.
--
-- This also restores 0098's answer validation (every chosen option must
-- belong to the slot; a rank answer must have exactly pick_count entries),
-- which 0111 silently dropped when it rebuilt do_resolve from 0095's text.

create function prompts_private.grade_slot(p_slot_id uuid, p_correct uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slot public.prompt_slots;
begin
  select * into v_slot from public.prompt_slots where id = p_slot_id;
  if not found then
    raise exception 'slot_not_found' using errcode = 'P0002';
  end if;

  if coalesce(array_length(p_correct, 1), 0) = 0
     or (v_slot.shape = 'rank' and array_length(p_correct, 1) <> v_slot.pick_count) then
    raise exception 'missing_answer' using errcode = '22023', detail = p_slot_id::text;
  end if;
  if exists (
    select 1 from unnest(p_correct) as answer (option_id)
    where not exists (
      select 1 from public.prompt_slot_options o where o.id = answer.option_id and o.slot_id = p_slot_id
    )
  ) then
    raise exception 'missing_answer' using errcode = '22023', detail = p_slot_id::text;
  end if;

  insert into private.prompt_slot_answers (slot_id, correct_option_ids)
  values (p_slot_id, p_correct)
  on conflict (slot_id) do update set correct_option_ids = excluded.correct_option_ids;

  -- The reveal (see 0094): same statement family as the scoring below, same
  -- transaction, so this slot is never visibly answered but ungraded.
  update public.prompt_slots set correct_option_ids = p_correct where id = p_slot_id;

  -- Mirrors logic.ts's scoreSlot: pick is exact-match-or-nothing; pick_set and
  -- rank pay points * (matches / total), rounded — overlap for pick_set,
  -- exact-position matches for rank.
  update public.prompt_responses r
     set points_earned = case v_slot.shape
       when 'pick' then
         case when r.chosen_option_ids[1] = p_correct[1] then v_slot.points else 0 end
       when 'pick_set' then
         round(v_slot.points::numeric
           * (select count(*) from unnest(r.chosen_option_ids) c where c = any (p_correct))
           / array_length(p_correct, 1))
       else -- rank
         round(v_slot.points::numeric
           * (
               select count(*)
               from unnest(r.chosen_option_ids) with ordinality as chosen (option_id, ord)
               join unnest(p_correct) with ordinality as truth (option_id, ord)
                 on chosen.ord = truth.ord and chosen.option_id = truth.option_id
             )
           / array_length(p_correct, 1))
     end
   where r.slot_id = p_slot_id;
end;
$$;

-- Grade one slot of a still-open post. Closes the post when no slot is left
-- ungraded. Re-grading an already-graded slot is allowed (an admin correcting
-- an answer before the post closes) — the automatic sweep never does it, since
-- it only looks at slots with no answer yet.
create function prompts_private.do_resolve_slot(p_slot_id uuid, p_correct uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts;
begin
  select p.* into v_post
    from public.prompt_posts p
   where p.id = (select s.post_id from public.prompt_slots s where s.id = p_slot_id)
     for update;
  if not found then
    raise exception 'slot_not_found' using errcode = 'P0002';
  end if;
  if v_post.is_opinion then
    raise exception 'opinion_not_resolvable' using errcode = '55000';
  end if;
  if v_post.status not in ('open', 'locked') then
    raise exception 'not_resolvable' using errcode = '55000';
  end if;

  perform prompts_private.grade_slot(p_slot_id, p_correct);

  if not exists (
    select 1 from public.prompt_slots where post_id = v_post.id and correct_option_ids is null
  ) then
    update public.prompt_posts set status = 'resolved', resolved_at = now() where id = v_post.id;
  end if;
end;
$$;

-- Whole-post resolution, unchanged in contract: p_answers is
-- {slot_id: [correct_option_id, ...]} with an entry for every slot, and the
-- post closes at the end. Used by prompts.resolve_post (admin) for shapes the
-- sweep can't derive (stat_leader, ranking, custom_multi).
create or replace function prompts_private.do_resolve(p_post_id uuid, p_answers jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts;
  v_slot record;
begin
  select * into v_post from public.prompt_posts where id = p_post_id for update;
  if not found then
    raise exception 'post_not_found' using errcode = 'P0002';
  end if;
  if v_post.is_opinion then
    raise exception 'opinion_not_resolvable' using errcode = '55000';
  end if;
  if v_post.status not in ('open', 'locked') then
    raise exception 'not_resolvable' using errcode = '55000';
  end if;

  for v_slot in select * from public.prompt_slots where post_id = p_post_id loop
    perform prompts_private.grade_slot(
      v_slot.id,
      array(select elem::uuid from jsonb_array_elements_text(p_answers -> v_slot.id::text) as elem)
    );
  end loop;

  update public.prompt_posts set status = 'resolved', resolved_at = now() where id = p_post_id;
end;
$$;

-- The automatic sweep, now slot by slot. Each ungraded winner slot on a due
-- post is looked up against the schedule on its own: a game that is not final
-- yet, a tie, or a team_code that matches neither side just leaves that slot
-- pending for the next tick, without holding back the slots that are ready.
create or replace function prompts_private.grade_due_game_picks(p_csv text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slot          record;
  v_game_id       text;
  v_line          text;
  v_away_team     text;
  v_away_score    text;
  v_home_team     text;
  v_home_score    text;
  v_winner_code   text;
  v_winner_option uuid;
begin
  for v_slot in
    select s.id as slot_id, s.source_game_id, p.id as post_id, p.resolution_source
      from public.prompt_slots s
      join public.prompt_posts p on p.id = s.post_id
     where p.status in ('open', 'locked') and p.lock_at <= now() and p.resolved_at is null
       and p.template_kind in ('picks', 'game_pick', 'weekly_picks') and p.resolution_source is not null
       and not p.is_opinion
       and s.correct_option_ids is null
     order by p.id, s.sort_order
  loop
    begin
      v_game_id := coalesce(v_slot.source_game_id, v_slot.resolution_source ->> 'game_id');
      continue when v_game_id is null;

      select l into v_line
        from unnest(string_to_array(p_csv, E'\n')) as l
       where l like v_game_id || ',%'
       limit 1;
      continue when v_line is null;

      v_away_team  := split_part(v_line, ',', 8);
      v_away_score := split_part(v_line, ',', 9);
      v_home_team  := split_part(v_line, ',', 10);
      v_home_score := split_part(v_line, ',', 11);
      continue when v_away_score = '' or v_home_score = '' or v_away_score = v_home_score;

      v_winner_code := case when v_home_score::int > v_away_score::int then v_home_team else v_away_team end;

      select id into v_winner_option
        from public.prompt_slot_options
       where slot_id = v_slot.slot_id and team_code = v_winner_code;
      continue when v_winner_option is null;

      perform prompts_private.do_resolve_slot(v_slot.slot_id, array[v_winner_option]);
    exception when others then
      raise warning 'auto_resolve_failed post_id=% slot_id=% sqlerrm=%', v_slot.post_id, v_slot.slot_id, sqlerrm;
    end;
  end loop;
end;
$$;

revoke all on function prompts_private.grade_slot(uuid, uuid[])       from public, anon, authenticated;
revoke all on function prompts_private.do_resolve_slot(uuid, uuid[])  from public, anon, authenticated;
-- do_resolve and grade_due_game_picks keep the grants they already had.
