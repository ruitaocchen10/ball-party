-- 0098 required pick_count on every rank slot and backfilled existing rows
-- from their option count, but left prompts.create_post writing pick_count
-- straight from the caller's payload -- so a new full-pool ranking (the
-- caller omits pick_count on purpose, meaning "rank all the options") now
-- fails prompt_slots_pick_count_shape_check on insert. Mirror 0098's own
-- backfill here: default a missing rank pick_count to the slot's option
-- count from the same JSON payload (the row isn't inserted yet, so this
-- reads the array rather than querying prompt_slot_options).
create or replace function prompts.create_post(
  p_template_kind       text,
  p_template_name       text,
  p_caption             text,
  p_prompt_text         text,
  p_resolution_criteria text,
  p_lock_at             timestamptz,
  p_slots               jsonb,
  p_resolution_source   jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user     uuid := auth.uid();
  v_post_id  uuid;
  v_slot     jsonb;
  v_option   jsonb;
  v_slot_id  uuid;
  v_slot_ids uuid[] := '{}';
  v_idx      int := 0;
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  insert into public.prompt_posts
    (template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, resolution_source)
  values
    (p_template_kind, p_template_name, v_user, p_caption, p_prompt_text, p_resolution_criteria, p_lock_at, p_resolution_source)
  returning id into v_post_id;

  for v_slot in select jsonb_array_elements(p_slots) loop
    insert into public.prompt_slots (post_id, label, shape, pick_count, points, sort_order, source_game_id)
    values (
      v_post_id, v_slot ->> 'label', v_slot ->> 'shape',
      coalesce(
        (v_slot ->> 'pick_count')::smallint,
        case when v_slot ->> 'shape' = 'rank'
          then jsonb_array_length(coalesce(v_slot -> 'options', '[]'::jsonb))::smallint
        end
      ),
      (v_slot ->> 'points')::smallint, v_idx, v_slot ->> 'source_game_id'
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
    from jsonb_array_elements_text(coalesce(v_slot -> 'excludes_slot_indexes', '[]'::jsonb)) as elem;
    v_idx := v_idx + 1;
  end loop;
  return v_post_id;
end;
$$;
