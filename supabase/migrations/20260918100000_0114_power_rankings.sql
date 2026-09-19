-- Power Rankings is an opinion-only, weekly team-ranking template. Unlike a
-- normal rank slot, the respondent — not the composer — chooses whether to
-- submit 5, 10, or all 32 teams.

alter table public.prompt_posts
  drop constraint prompt_posts_template_kind_check,
  add constraint prompt_posts_template_kind_check
    check (template_kind in ('picks', 'game_pick', 'weekly_picks', 'stat_leader', 'ranking', 'power_rankings', 'custom_multi')),
  add constraint prompt_posts_power_rankings_opinion_check
    check (template_kind <> 'power_rankings' or is_opinion);

create or replace function prompts.create_post(
  p_template_kind       text,
  p_template_name       text,
  p_caption             text,
  p_prompt_text         text,
  p_resolution_criteria text,
  p_lock_at             timestamptz,
  p_slots               jsonb,
  p_resolution_source   jsonb default null,
  p_is_opinion          boolean default false
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
  end if;

  insert into public.prompt_posts
    (template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, resolution_source, is_opinion)
  values
    (p_template_kind, p_template_name, v_user, p_caption, p_prompt_text, p_resolution_criteria, p_lock_at, p_resolution_source, p_is_opinion)
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
      insert into public.prompt_slot_options (slot_id, label, sublabel, team_code, headshot_url, sort_order)
      values (v_slot_id, v_option ->> 'label', v_option ->> 'sublabel', v_option ->> 'team_code', v_option ->> 'headshot_url', coalesce((v_option ->> 'sort_order')::smallint, 0));
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

create or replace function prompts.submit_response(p_post_id uuid, p_choices jsonb, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user         uuid := auth.uid();
  v_post         public.prompt_posts;
  v_slot         record;
  v_option_ids   uuid[];
  v_expected_count int;
  v_choice_count int;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_post from public.prompt_posts where id = p_post_id for update;
  if not found then raise exception 'post_not_found' using errcode = 'P0002'; end if;
  if v_post.status <> 'open' or now() >= v_post.lock_at then raise exception 'post_locked' using errcode = '55000'; end if;

  for v_slot in select * from public.prompt_slots where post_id = p_post_id loop
    v_option_ids := array(select elem::uuid from jsonb_array_elements_text(coalesce(p_choices -> v_slot.id::text, '[]'::jsonb)) elem);
    v_choice_count := coalesce(array_length(v_option_ids, 1), 0);
    v_expected_count := case v_slot.shape when 'pick' then 1 else v_slot.pick_count end;

    if (v_post.template_kind = 'power_rankings' and (v_choice_count not in (5, 10, 32)))
       or (v_post.template_kind <> 'power_rankings' and v_choice_count <> v_expected_count)
       or (select count(distinct option_id) from unnest(v_option_ids) option_id) <> v_choice_count then
      raise exception 'incomplete_slot' using errcode = '22023', detail = v_slot.id::text;
    end if;
    if exists (
      select 1 from unnest(v_option_ids) option_id
      where not exists (select 1 from public.prompt_slot_options option where option.id = option_id and option.slot_id = v_slot.id)
    ) then raise exception 'invalid_option' using errcode = '22023', detail = v_slot.id::text;
    end if;

    insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids)
    values (p_post_id, v_slot.id, v_user, v_option_ids)
    on conflict (slot_id, profile_id) do update set chosen_option_ids = excluded.chosen_option_ids;
  end loop;

  if exists (
    select 1 from public.prompt_slot_exclusions exclusion
    join public.prompt_responses mine on mine.slot_id = exclusion.slot_id and mine.profile_id = v_user
    join public.prompt_responses theirs on theirs.slot_id = exclusion.excluded_slot_id and theirs.profile_id = v_user
    join public.prompt_slot_options mine_option on mine_option.id = any (mine.chosen_option_ids)
    join public.prompt_slot_options their_option on their_option.id = any (theirs.chosen_option_ids)
    where mine.post_id = p_post_id and mine_option.team_code is not null and mine_option.team_code = their_option.team_code
  ) then raise exception 'option_already_used' using errcode = '22023'; end if;

  if p_comment is not null and length(trim(p_comment)) > 0 then
    insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
    values (p_post_id, v_user, trim(p_comment), true);
  end if;
end;
$$;
