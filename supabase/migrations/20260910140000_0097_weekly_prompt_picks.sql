-- A winner-pick post can be either one game or a curated/full weekly slate.
-- The game's nflverse identity lives on the slot so every slot can be graded
-- independently while users still answer one social prompt.

alter table public.prompt_posts
  drop constraint prompt_posts_template_kind_check,
  add constraint prompt_posts_template_kind_check
    check (template_kind in ('game_pick', 'weekly_picks', 'stat_leader', 'ranking', 'custom_multi'));

alter table public.prompt_slots
  add column source_game_id text;

alter table public.prompt_posts
  drop constraint prompt_posts_resolution_source_check,
  add constraint prompt_posts_resolution_source_check check (
    resolution_source is null or (
      resolution_source ->> 'provider' = 'nflverse'
      and resolution_source ->> 'rule' = 'winner'
    )
  );

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
      v_post_id, v_slot ->> 'label', v_slot ->> 'shape', (v_slot ->> 'pick_count')::smallint,
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

create or replace function prompts_private.grade_due_game_picks(p_csv text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post          public.prompt_posts;
  v_slot          record;
  v_line          text;
  v_game_id       text;
  v_away_team     text;
  v_away_score    text;
  v_home_team     text;
  v_home_score    text;
  v_winner_code   text;
  v_winner_option uuid;
  v_answers       jsonb;
  v_incomplete    boolean;
begin
  for v_post in
    select * from public.prompt_posts
     where status in ('open', 'locked') and lock_at <= now() and resolved_at is null
       and template_kind in ('game_pick', 'weekly_picks') and resolution_source is not null
  loop
    begin
      v_answers := '{}'::jsonb;
      v_incomplete := false;
      for v_slot in select * from public.prompt_slots where post_id = v_post.id loop
        -- game_id on the post is retained as a backwards-compatible fallback
        -- for the original single-game posts created before this migration.
        v_game_id := coalesce(v_slot.source_game_id, v_post.resolution_source ->> 'game_id');
        if v_game_id is null then v_incomplete := true; exit; end if;
        select l into v_line from unnest(string_to_array(p_csv, E'\n')) as l where l like v_game_id || ',%' limit 1;
        if v_line is null then v_incomplete := true; exit; end if;
        v_away_team := split_part(v_line, ',', 8);
        v_away_score := split_part(v_line, ',', 9);
        v_home_team := split_part(v_line, ',', 10);
        v_home_score := split_part(v_line, ',', 11);
        if v_away_score = '' or v_home_score = '' or v_away_score = v_home_score then v_incomplete := true; exit; end if;
        v_winner_code := case when v_home_score::int > v_away_score::int then v_home_team else v_away_team end;
        select id into v_winner_option from public.prompt_slot_options where slot_id = v_slot.id and team_code = v_winner_code;
        if v_winner_option is null then v_incomplete := true; exit; end if;
        v_answers := v_answers || jsonb_build_object(v_slot.id::text, jsonb_build_array(v_winner_option::text));
      end loop;
      if not v_incomplete then perform prompts_private.do_resolve(v_post.id, v_answers); end if;
    exception when others then
      raise warning 'auto_resolve_failed post_id=% sqlerrm=%', v_post.id, sqlerrm;
    end;
  end loop;
end;
$$;
