-- Opinion prompts: a cross-cutting characteristic, not a new template_kind.
-- Any existing template shape (picks, stat_leader, ranking, custom_multi) can
-- be asked either as a real-outcome question or as pure debate with no
-- correct answer at all — "best trade this season?" is just as much a
-- custom_multi/stat_leader shape as a graded one is. is_opinion says which,
-- independent of shape.
--
-- An opinion post is never resolvable: do_resolve (0095) is the single choke
-- point both prompts.resolve_post (admin) and grade_due_game_picks
-- (auto-resolve, 0096/0100) call through, so one guard there closes both
-- paths at once, same reasoning 0095's own header comment gives for why that
-- function needs no separate authorization check of its own.

alter table public.prompt_posts
  add column is_opinion boolean not null default false;

-- resolution_source exists purely so the auto-resolve sweep can grade a
-- picks post off a real game's score — meaningless, and actively
-- contradictory, on a post declared to have no correct answer.
alter table public.prompt_posts
  add constraint prompt_posts_opinion_no_auto_source
  check (not is_opinion or resolution_source is null);

create or replace function prompts_private.do_resolve(p_post_id uuid, p_answers jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post    public.prompt_posts;
  v_slot    record;
  v_correct uuid[];
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
    v_correct := array(
      select elem::uuid
      from jsonb_array_elements_text(p_answers -> v_slot.id::text) as elem
    );
    if coalesce(array_length(v_correct, 1), 0) = 0 then
      raise exception 'missing_answer' using errcode = '22023', detail = v_slot.id::text;
    end if;

    insert into private.prompt_slot_answers (slot_id, correct_option_ids)
    values (v_slot.id, v_correct)
    on conflict (slot_id) do update set correct_option_ids = excluded.correct_option_ids;

    update public.prompt_slots set correct_option_ids = v_correct where id = v_slot.id;

    update public.prompt_responses r
       set points_earned = case v_slot.shape
         when 'pick' then
           case when r.chosen_option_ids[1] = v_correct[1] then v_slot.points else 0 end
         when 'pick_set' then
           round(v_slot.points::numeric
             * (select count(*) from unnest(r.chosen_option_ids) c where c = any (v_correct))
             / array_length(v_correct, 1))
         else -- rank
           round(v_slot.points::numeric
             * (
                 select count(*)
                 from unnest(r.chosen_option_ids) with ordinality as chosen (option_id, ord)
                 join unnest(v_correct) with ordinality as truth (option_id, ord)
                   on chosen.ord = truth.ord and chosen.option_id = truth.option_id
               )
             / array_length(v_correct, 1))
       end
     where r.slot_id = v_slot.id;
  end loop;

  update public.prompt_posts set status = 'resolved', resolved_at = now() where id = p_post_id;
end;
$$;

-- create_post gains a parameter, so this repo's convention for a changed
-- signature applies (see 0004/0017/0029): drop the old signature explicitly
-- rather than let create or replace leave two overloads behind.
drop function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb);

create function prompts.create_post(
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
      -- 0104: a full-pool ranking omits pick_count on purpose ("rank all the
      -- options"), which needs backfilling from the option count here or the
      -- insert fails prompt_slots_pick_count_shape_check.
      coalesce(
        (v_slot ->> 'pick_count')::smallint,
        case when v_slot ->> 'shape' = 'rank'
          then jsonb_array_length(coalesce(v_slot -> 'options', '[]'::jsonb))::smallint
        end
      ),
      (v_slot ->> 'points')::smallint,
      v_idx,
      v_slot ->> 'source_game_id'
    )
    returning id into v_slot_id;

    v_slot_ids := v_slot_ids || v_slot_id;

    for v_option in select jsonb_array_elements(coalesce(v_slot -> 'options', '[]'::jsonb)) loop
      insert into public.prompt_slot_options (slot_id, label, sublabel, team_code, headshot_url, sort_order)
      values (
        v_slot_id,
        v_option ->> 'label',
        v_option ->> 'sublabel',
        v_option ->> 'team_code',
        v_option ->> 'headshot_url',
        coalesce((v_option ->> 'sort_order')::smallint, 0)
      );
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

revoke all on function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb, boolean) from public, anon;
grant execute on function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb, boolean) to authenticated;

-- Explicit, readable defense-in-depth alongside item 2's constraint (an
-- opinion post can never have a resolution_source to begin with) rather than
-- relying on that alone.
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
       and template_kind in ('picks', 'game_pick', 'weekly_picks') and resolution_source is not null
       and not is_opinion
  loop
    begin
      v_answers := '{}'::jsonb;
      v_incomplete := false;
      for v_slot in select * from public.prompt_slots where post_id = v_post.id loop
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

create or replace function prompts_private.auto_resolve_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll    prompts_private.nflverse_poll;
  v_status  int;
  v_content text;
begin
  select * into v_poll from prompts_private.nflverse_poll where id;

  if v_poll.request_id is not null then
    select r.status_code, r.content into v_status, v_content
      from net._http_response r
     where r.id = v_poll.request_id;

    if found and v_status = 200 then
      perform prompts_private.grade_due_game_picks(v_content);
    end if;
  end if;

  if exists (
    select 1 from public.prompt_posts
     where status in ('open', 'locked') and lock_at <= now() and resolved_at is null
       and template_kind in ('picks', 'game_pick', 'weekly_picks')
       and resolution_source is not null
       and not is_opinion
  ) then
    update prompts_private.nflverse_poll
       set request_id = net.http_get(
             url := 'https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv',
             timeout_milliseconds := 20000
           ),
           requested_at = now()
     where id;
  else
    update prompts_private.nflverse_poll set request_id = null, requested_at = null where id;
  end if;
end;
$$;
