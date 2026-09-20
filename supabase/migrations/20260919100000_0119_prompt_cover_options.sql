-- A "pick one" (stat_leader) prompt's art has room for four candidates. When
-- the pool is larger, the admin chooses which four the art shows and in what
-- order — the same idea as a Power Rankings cover (0118), except the pool here
-- is players, who have no stable id to store. The choice therefore lives on
-- the option row itself: cover_position 1–4, null for a candidate that isn't
-- in the art. Every candidate stays answerable; this only controls the art.

alter table public.prompt_slot_options add column cover_position smallint;

alter table public.prompt_slot_options
  add constraint prompt_slot_options_cover_position_check
    check (cover_position between 1 and 4);

-- One candidate per art position within a slot.
create unique index prompt_slot_options_cover_position_unique
  on public.prompt_slot_options (slot_id, cover_position)
  where cover_position is not null;

-- Same body as 0118's, with two additions: an option's cover_position is
-- validated up front and then stored. A slot's positions must be exactly
-- 1..k (no gaps, no repeats, at most four), and only a stat_leader post may
-- carry any. The signature is unchanged — positions ride inside p_slots — so
-- the existing grants still apply.
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
      insert into public.prompt_slot_options (slot_id, label, sublabel, team_code, headshot_url, sort_order, cover_position)
      values (
        v_slot_id,
        v_option ->> 'label',
        v_option ->> 'sublabel',
        v_option ->> 'team_code',
        v_option ->> 'headshot_url',
        coalesce((v_option ->> 'sort_order')::smallint, 0),
        (v_option ->> 'cover_position')::smallint
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
