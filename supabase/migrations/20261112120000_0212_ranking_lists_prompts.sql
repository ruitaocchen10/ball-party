-- Ranking lists (3/3): prompt answers feed lists, and existing Power Rankings
-- responses become list versions.
--
-- Answering a ranking prompt (a post with ranking_kind set) stays one card, the
-- prompt's own take card, and also writes the player's list version for that
-- prompt in the same transaction. prompt_responses is untouched, so consensus,
-- "matched N of 5" and points keep working. Resubmitting before the prompt
-- locks overwrites the version (the open window is the draft); after lock it
-- is never touched again.

-- Writes (or overwrites) the player's version for a prompt. Not capped: prompt
-- answers are exempt from the daily edit limit.
create function private.ranking_save_prompt_version(p_profile uuid, p_kind text, p_post uuid, p_items text[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list    uuid;
  v_version uuid;
begin
  perform private.ranking_check_items(p_kind, p_items);
  v_list := private.ranking_ensure_list(p_profile, p_kind);

  select id into v_version from public.ranking_list_versions where list_id = v_list and post_id = p_post;
  if found then
    update public.ranking_list_versions set updated_at = now() where id = v_version;
  else
    v_version := private.ranking_new_version(v_list, 'prompt', p_post, null);
  end if;
  perform private.ranking_replace_items(v_version, p_kind, p_items);
  return v_version;
end;
$$;

revoke all on function private.ranking_save_prompt_version(uuid, text, uuid, text[]) from public, anon, authenticated;

-- submit_response (latest body: 0208) with one addition, just before the take
-- is written: a ranking prompt also saves the answer as a list version.
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
  v_player_ids   text[];
  v_player       prompts_private.nfl_players;
  v_option_id    uuid;
  v_expected_count int;
  v_choice_count int;
  v_body         text := coalesce(trim(p_comment), '');
  v_take         uuid;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_post from public.prompt_posts where id = p_post_id for update;
  if not found then raise exception 'post_not_found' using errcode = 'P0002'; end if;
  if v_post.status <> 'open' or now() >= v_post.lock_at then raise exception 'post_locked' using errcode = '55000'; end if;

  for v_slot in select * from public.prompt_slots where post_id = p_post_id loop
    if v_slot.player_search then
      v_player_ids := array(select elem from jsonb_array_elements_text(coalesce(p_choices -> v_slot.id::text, '[]'::jsonb)) elem);
      if coalesce(array_length(v_player_ids, 1), 0) <> 1 then
        raise exception 'incomplete_slot' using errcode = '22023', detail = v_slot.id::text;
      end if;
      select * into v_player from prompts_private.nfl_players where player_id = v_player_ids[1];
      if not found then
        raise exception 'invalid_option' using errcode = '22023', detail = v_slot.id::text;
      end if;

      insert into public.prompt_slot_options (slot_id, label, sublabel, team_code, headshot_url, player_id)
      values (v_slot.id, v_player.display_name, v_player.position || ' · ' || v_player.team, v_player.team, v_player.headshot_url, v_player.player_id)
      on conflict (slot_id, player_id) where player_id is not null do nothing;
      select id into v_option_id from public.prompt_slot_options where slot_id = v_slot.id and player_id = v_player.player_id;
      v_option_ids := array[v_option_id];
    else
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

  -- A ranking prompt: the answer is also a version of the player's list. The
  -- ranking is the post's rank slot, in the order the player chose.
  if v_post.ranking_kind is not null then
    perform private.ranking_save_prompt_version(v_user, v_post.ranking_kind, p_post_id, (
      select array_agg(case k.item_kind when 'team' then o.team_code else o.player_id end order by u.ord)
        from public.prompt_responses r
        join public.prompt_slots s on s.id = r.slot_id and s.shape = 'rank'
        join public.ranking_list_kinds k on k.id = v_post.ranking_kind
        cross join lateral unnest(r.chosen_option_ids) with ordinality as u(option_id, ord)
        join public.prompt_slot_options o on o.id = u.option_id
       where r.post_id = p_post_id and r.profile_id = v_user
    ));
  end if;

  select id into v_take from public.prompt_comments
   where post_id = p_post_id and author_id = v_user and posted_with_pick and parent_comment_id is null
   order by created_at limit 1;
  if v_take is null then
    insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
    values (p_post_id, v_user, v_body, true);
  elsif v_body <> '' then
    update public.prompt_comments set body = v_body where id = v_take;
  end if;
end;
$$;

-- ----------------------------------------------------------------- backfill --

-- Turns every existing Power Rankings response into a prompt-sourced version,
-- oldest post first, with the response's own timestamp. Idempotent: a response
-- that already has a version is skipped, so a re-run only adds what is missing.
create function private.ranking_backfill_power_rankings()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_added integer;
begin
  insert into public.ranking_lists (profile_id, kind)
  select distinct r.profile_id, 'power_rankings'
    from public.prompt_responses r
    join public.prompt_posts p on p.id = r.post_id and p.template_kind = 'power_rankings'
    join public.profiles pr on pr.id = r.profile_id and pr.deleted_at is null
  on conflict (profile_id, kind) do nothing;

  with todo as (
    select l.id as list_id, r.post_id, r.created_at, r.chosen_option_ids, p.created_at as post_created
      from public.prompt_responses r
      join public.prompt_posts p on p.id = r.post_id and p.template_kind = 'power_rankings'
      join public.ranking_lists l on l.profile_id = r.profile_id and l.kind = 'power_rankings'
     where not exists (
       select 1 from public.ranking_list_versions v where v.list_id = l.id and v.post_id = r.post_id)
  ),
  numbered as (
    select t.*,
           coalesce((select max(v.version_no) from public.ranking_list_versions v where v.list_id = t.list_id), 0)
             + row_number() over (partition by t.list_id order by t.post_created, t.created_at) as version_no
      from todo t
  ),
  made as (
    insert into public.ranking_list_versions (list_id, version_no, source, post_id, created_at, updated_at)
    select list_id, version_no, 'prompt', post_id, created_at, created_at from numbered
    returning id, list_id, post_id
  ),
  filled as (
    insert into public.ranking_list_items (version_id, place, team_code)
    select m.id, u.ord::smallint, o.team_code
      from made m
      join numbered n on n.list_id = m.list_id and n.post_id = m.post_id
      cross join lateral unnest(n.chosen_option_ids) with ordinality as u(option_id, ord)
      join public.prompt_slot_options o on o.id = u.option_id
    returning 1
  )
  select count(*) into v_added from made;

  update public.ranking_lists l
     set current_version_id = (
       select v.id from public.ranking_list_versions v where v.list_id = l.id order by v.version_no desc limit 1)
   where l.kind = 'power_rankings';

  return v_added;
end;
$$;

revoke all on function private.ranking_backfill_power_rankings() from public, anon, authenticated;

select private.ranking_backfill_power_rankings();
