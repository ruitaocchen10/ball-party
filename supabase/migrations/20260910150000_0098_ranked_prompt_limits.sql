-- A ranking can ask for a top N rather than forcing every candidate into an
-- order. `pick_count` is that N for rank slots (and remains the set size for
-- pick_set slots).

update public.prompt_slots slot
set pick_count = (
  select count(*)::smallint from public.prompt_slot_options option where option.slot_id = slot.id
)
where slot.shape = 'rank' and slot.pick_count is null;

do $$
declare
  v_constraint text;
begin
  select conname into v_constraint
  from pg_constraint
  where conrelid = 'public.prompt_slots'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%shape = ''pick_set''%'
  limit 1;

  if v_constraint is not null then
    execute format('alter table public.prompt_slots drop constraint %I', v_constraint);
  end if;
end $$;

alter table public.prompt_slots
  add constraint prompt_slots_pick_count_shape_check
    check ((shape in ('pick_set', 'rank')) = (pick_count is not null));

-- Existing rankings were backfilled above, so this expected count works for
-- both historical full-pool ranks and newly authored top-N ranks.
create or replace function prompts.submit_response(p_post_id uuid, p_choices jsonb, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_post public.prompt_posts;
  v_slot record;
  v_option_ids uuid[];
  v_expected_count int;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_post from public.prompt_posts where id = p_post_id for update;
  if not found then raise exception 'post_not_found' using errcode = 'P0002'; end if;
  if v_post.status <> 'open' or now() >= v_post.lock_at then
    raise exception 'post_locked' using errcode = '55000';
  end if;

  for v_slot in select * from public.prompt_slots where post_id = p_post_id loop
    v_option_ids := array(
      select elem::uuid
      from jsonb_array_elements_text(coalesce(p_choices -> v_slot.id::text, '[]'::jsonb)) as elem
    );
    v_expected_count := case v_slot.shape
      when 'pick' then 1
      else v_slot.pick_count
    end;

    if coalesce(array_length(v_option_ids, 1), 0) <> v_expected_count
       or (select count(distinct x) from unnest(v_option_ids) x) <> v_expected_count then
      raise exception 'incomplete_slot' using errcode = '22023', detail = v_slot.id::text;
    end if;
    if exists (
      select 1 from unnest(v_option_ids) oid
      where not exists (select 1 from public.prompt_slot_options option where option.id = oid and option.slot_id = v_slot.id)
    ) then raise exception 'invalid_option' using errcode = '22023', detail = v_slot.id::text;
    end if;

    insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids)
    values (p_post_id, v_slot.id, v_user, v_option_ids)
    on conflict (slot_id, profile_id) do update set chosen_option_ids = excluded.chosen_option_ids;
  end loop;

  if exists (
    select 1
    from public.prompt_slot_exclusions exclusion
    join public.prompt_responses mine on mine.slot_id = exclusion.slot_id and mine.profile_id = v_user
    join public.prompt_responses theirs on theirs.slot_id = exclusion.excluded_slot_id and theirs.profile_id = v_user
    join public.prompt_slot_options mine_option on mine_option.id = any (mine.chosen_option_ids)
    join public.prompt_slot_options their_option on their_option.id = any (theirs.chosen_option_ids)
    where mine.post_id = p_post_id and mine_option.team_code is not null and mine_option.team_code = their_option.team_code
  ) then raise exception 'option_already_used' using errcode = '22023';
  end if;

  if p_comment is not null and length(trim(p_comment)) > 0 then
    insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
    values (p_post_id, v_user, trim(p_comment), true);
  end if;
end;
$$;

-- The published answer must use the same top-N shape the players saw. This
-- also prevents a resolver from accidentally grading a rank against a longer
-- or shorter ordering than the response contract.
create or replace function prompts_private.do_resolve(p_post_id uuid, p_answers jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts;
  v_slot record;
  v_correct uuid[];
begin
  select * into v_post from public.prompt_posts where id = p_post_id for update;
  if not found then raise exception 'post_not_found' using errcode = 'P0002'; end if;
  if v_post.status not in ('open', 'locked') then raise exception 'not_resolvable' using errcode = '55000'; end if;

  for v_slot in select * from public.prompt_slots where post_id = p_post_id loop
    v_correct := array(select elem::uuid from jsonb_array_elements_text(p_answers -> v_slot.id::text) as elem);
    if coalesce(array_length(v_correct, 1), 0) = 0
       or (v_slot.shape = 'rank' and array_length(v_correct, 1) <> v_slot.pick_count) then
      raise exception 'missing_answer' using errcode = '22023', detail = v_slot.id::text;
    end if;
    if exists (
      select 1 from unnest(v_correct) oid
      where not exists (select 1 from public.prompt_slot_options option where option.id = oid and option.slot_id = v_slot.id)
    ) then raise exception 'missing_answer' using errcode = '22023', detail = v_slot.id::text;
    end if;

    insert into private.prompt_slot_answers (slot_id, correct_option_ids)
    values (v_slot.id, v_correct)
    on conflict (slot_id) do update set correct_option_ids = excluded.correct_option_ids;
    update public.prompt_slots set correct_option_ids = v_correct where id = v_slot.id;

    update public.prompt_responses response
    set points_earned = case v_slot.shape
      when 'pick' then case when response.chosen_option_ids[1] = v_correct[1] then v_slot.points else 0 end
      when 'pick_set' then round(v_slot.points::numeric * (
        select count(*) from unnest(response.chosen_option_ids) choice where choice = any (v_correct)
      ) / array_length(v_correct, 1))
      else round(v_slot.points::numeric * (
        select count(*)
        from unnest(response.chosen_option_ids) with ordinality as chosen (option_id, ord)
        join unnest(v_correct) with ordinality as truth (option_id, ord)
          on chosen.ord = truth.ord and chosen.option_id = truth.option_id
      ) / array_length(v_correct, 1))
    end where response.slot_id = v_slot.id;
  end loop;

  update public.prompt_posts set status = 'resolved', resolved_at = now() where id = p_post_id;
end;
$$;
