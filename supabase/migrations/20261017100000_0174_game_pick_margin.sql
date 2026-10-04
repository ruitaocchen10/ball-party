-- Prompt types 2/7: a Game Picks post is one slot with four options — the
-- winner and whether the margin was under 7 or 7+ (exactly 7 is "7+"). Every
-- option keeps its team_code (team art, winner lookup); the new `margin`
-- column says which bucket it is. A slot whose options carry no margin is a
-- pre-split winner-only pick and is graded as before.
--
-- Also here:
--   * create_post (0119's body) stores option.margin.
--   * grade_due_game_picks (0117) derives the winning option from the score
--     and margin. A tied game voids a game_pick post ("Game ended in a tie");
--     on any other Picks post it grades just that slot as no-contest, so one
--     tie no longer holds the rest of a weekly slate back forever.
--
-- "No contest": the slot's correct_option_ids is revealed as the empty array,
-- every response to it earns 0, and the slot counts as graded so the post can
-- close. Profile stats (0107-0109) only sum points_earned over resolved posts,
-- so a no-contest slot is simply worth nothing to anyone.

alter table public.prompt_slot_options add column margin text;
alter table public.prompt_slot_options
  add constraint prompt_slot_options_margin_check check (margin in ('under_7', '7_plus'));

-- create_post: 0119's body plus option.margin (signature unchanged, grants kept).
create or replace function prompts.create_post(
  p_template_kind       text,
  p_template_name       text,
  p_caption             text,
  p_prompt_text         text,
  p_resolution_criteria text,
  p_lock_at             timestamptz,
  p_slots               jsonb,
  p_resolution_source   jsonb default null,
  p_is_opinion          boolean default false,
  p_cover_team_codes    text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user         uuid := auth.uid();
  v_post_id      uuid;
  v_slot         jsonb;
  v_option       jsonb;
  v_slot_id      uuid;
  v_slot_ids     uuid[] := '{}';
  v_idx          int := 0;
  v_option_count int;
  v_team_count   int;
  v_missing_code int;
  v_positions    int[];
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- Keep the cross-week comparison meaningful: every Power Rankings post is
  -- exactly one, full-league team slot, and it can never be graded.
  if p_template_kind = 'power_rankings' then
    select count(*), count(distinct option ->> 'team_code'), count(*) filter (where coalesce(option ->> 'team_code', '') = '')
      into v_option_count, v_team_count, v_missing_code
      from jsonb_array_elements(coalesce(p_slots -> 0 -> 'options', '[]'::jsonb)) option;
    if not p_is_opinion
       or p_resolution_source is not null
       or jsonb_array_length(p_slots) <> 1
       or p_slots -> 0 ->> 'shape' <> 'rank'
       or coalesce((p_slots -> 0 ->> 'pick_count')::int, 0) <> 32
       or v_option_count <> 32
       or v_team_count <> 32
       or v_missing_code <> 0 then
      raise exception 'invalid_power_rankings' using errcode = '22023';
    end if;

    -- The cover is six distinct teams from this post's own pool.
    if cardinality(p_cover_team_codes) is distinct from 6
       or (select count(distinct code) from unnest(p_cover_team_codes) code) <> 6
       or exists (
         select 1 from unnest(p_cover_team_codes) code
         where not exists (
           select 1 from jsonb_array_elements(p_slots -> 0 -> 'options') option where option ->> 'team_code' = code
         )
       ) then
      raise exception 'invalid_cover_teams' using errcode = '22023';
    end if;
  elsif p_cover_team_codes is not null then
    raise exception 'invalid_cover_teams' using errcode = '22023';
  end if;

  -- The art positions on a slot's options: 1..k, at most four, stat_leader only.
  for v_slot in select jsonb_array_elements(p_slots) loop
    select coalesce(array_agg((option ->> 'cover_position')::int order by (option ->> 'cover_position')::int), '{}')
      into v_positions
      from jsonb_array_elements(coalesce(v_slot -> 'options', '[]'::jsonb)) option
      where option ->> 'cover_position' is not null;
    if cardinality(v_positions) > 0
       and (p_template_kind <> 'stat_leader'
            or cardinality(v_positions) > 4
            or v_positions <> array(select generate_series(1, cardinality(v_positions)))) then
      raise exception 'invalid_cover_options' using errcode = '22023';
    end if;
  end loop;

  insert into public.prompt_posts
    (template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, resolution_source, is_opinion, cover_team_codes)
  values
    (p_template_kind, p_template_name, v_user, p_caption, p_prompt_text, p_resolution_criteria, p_lock_at, p_resolution_source, p_is_opinion, p_cover_team_codes)
  returning id into v_post_id;

  for v_slot in select jsonb_array_elements(p_slots) loop
    insert into public.prompt_slots (post_id, label, shape, pick_count, points, sort_order, source_game_id)
    values (
      v_post_id,
      v_slot ->> 'label',
      v_slot ->> 'shape',
      coalesce((v_slot ->> 'pick_count')::smallint, case when v_slot ->> 'shape' = 'rank' then jsonb_array_length(coalesce(v_slot -> 'options', '[]'::jsonb))::smallint end),
      (v_slot ->> 'points')::smallint,
      v_idx,
      v_slot ->> 'source_game_id'
    ) returning id into v_slot_id;
    v_slot_ids := v_slot_ids || v_slot_id;

    for v_option in select jsonb_array_elements(coalesce(v_slot -> 'options', '[]'::jsonb)) loop
      insert into public.prompt_slot_options (slot_id, label, sublabel, team_code, headshot_url, sort_order, cover_position, margin)
      values (
        v_slot_id,
        v_option ->> 'label',
        v_option ->> 'sublabel',
        v_option ->> 'team_code',
        v_option ->> 'headshot_url',
        coalesce((v_option ->> 'sort_order')::smallint, 0),
        (v_option ->> 'cover_position')::smallint,
        v_option ->> 'margin'
      );
    end loop;
    v_idx := v_idx + 1;
  end loop;

  v_idx := 0;
  for v_slot in select jsonb_array_elements(p_slots) loop
    insert into public.prompt_slot_exclusions (slot_id, excluded_slot_id)
    select v_slot_ids[v_idx + 1], v_slot_ids[(elem)::int + 1]
    from jsonb_array_elements_text(coalesce(v_slot -> 'excludes_slot_indexes', '[]'::jsonb)) elem;
    v_idx := v_idx + 1;
  end loop;
  return v_post_id;
end;
$$;

-- Grade a slot as no contest (see header). Same guards as do_resolve_slot.
create function prompts_private.do_no_contest_slot(p_slot_id uuid)
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

  update public.prompt_slots set correct_option_ids = '{}' where id = p_slot_id;
  update public.prompt_responses set points_earned = 0 where slot_id = p_slot_id;

  if not exists (
    select 1 from public.prompt_slots where post_id = v_post.id and correct_option_ids is null
  ) then
    update public.prompt_posts set status = 'resolved', resolved_at = now() where id = v_post.id;
  end if;
end;
$$;

revoke all on function prompts_private.do_no_contest_slot(uuid) from public, anon, authenticated;

-- 0117's sweep with the margin and tie rules. A game that is not final yet, or
-- whose derived option can't be found, still just stays pending for the next tick.
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
  v_margin        int;
  v_has_margin    boolean;
  v_winner_option uuid;
begin
  for v_slot in
    select s.id as slot_id, s.source_game_id, p.id as post_id, p.template_kind, p.resolution_source
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
      continue when v_away_score = '' or v_home_score = '';

      if v_away_score = v_home_score then
        if v_slot.template_kind = 'game_pick' then
          update public.prompt_posts
             set status = 'void', void_reason = 'Game ended in a tie'
           where id = v_slot.post_id and status in ('open', 'locked');
        else
          perform prompts_private.do_no_contest_slot(v_slot.slot_id);
        end if;
        continue;
      end if;

      v_winner_code := case when v_home_score::int > v_away_score::int then v_home_team else v_away_team end;
      v_margin := abs(v_home_score::int - v_away_score::int);
      select bool_or(margin is not null) into v_has_margin
        from public.prompt_slot_options where slot_id = v_slot.slot_id;

      select id into v_winner_option
        from public.prompt_slot_options
       where slot_id = v_slot.slot_id and team_code = v_winner_code
         and (not v_has_margin or margin = case when v_margin >= 7 then '7_plus' else 'under_7' end);
      continue when v_winner_option is null;

      perform prompts_private.do_resolve_slot(v_slot.slot_id, array[v_winner_option]);
    exception when others then
      raise warning 'auto_resolve_failed post_id=% slot_id=% sqlerrm=%', v_slot.post_id, v_slot.slot_id, sqlerrm;
    end;
  end loop;
end;
$$;
