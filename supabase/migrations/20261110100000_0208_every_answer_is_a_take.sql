-- Every answer is a take.
--
-- A take is the row a reply thread hangs on (prompt_comments, replies point at
-- it through parent_comment_id). Until now an answer only had one if its author
-- also wrote something, so a player who just picked had no card to comment on,
-- and Bold Predictions (which live in their own table) never had one. Now
-- answering always leaves a take, with an empty body when the player wrote
-- nothing, so every card is the same kind of thing: it has a thread page, a
-- reply count, reply notifications, and its picks behind View take.

-- An empty body is allowed on exactly one kind of row: a top-level take posted
-- with picks. A reply, or a take posted without picks, still needs 1-280 chars.
alter table public.prompt_comments drop constraint prompt_comments_body_check;
alter table public.prompt_comments add constraint prompt_comments_body_check check (
  char_length(trim(body)) <= 280
  and (char_length(trim(body)) >= 1 or (posted_with_pick and parent_comment_id is null))
);

-- submit_response (latest body: 0175/0178 era) with one change at the end: the
-- take is always written, and a resubmit fills in an empty one rather than
-- adding a second.
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

-- Bold Predictions: the person's predictions stay in bold_predictions; their
-- take is the empty card those predictions hang on.
create or replace function prompts.submit_bold_predictions(p_post_id uuid, p_predictions jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts := prompts_private.bold_writable_post(p_post_id);
  v_item jsonb;
begin
  if p_predictions is null or jsonb_typeof(p_predictions) <> 'array' or jsonb_array_length(p_predictions) = 0 then
    raise exception 'no_predictions' using errcode = '22023';
  end if;
  if jsonb_array_length(p_predictions) > 5 then
    raise exception 'too_many_predictions' using errcode = '54000';
  end if;

  -- Same key the cap trigger takes, so two concurrent submits serialize here.
  perform pg_advisory_xact_lock(hashtextextended(p_post_id::text || ':' || auth.uid()::text, 0));
  if exists (select 1 from public.bold_predictions where post_id = p_post_id and author_id = auth.uid()) then
    raise exception 'already_answered' using errcode = '23505';
  end if;

  for v_item in select * from jsonb_array_elements(p_predictions) loop
    perform prompts_private.validate_bold_target(v_post, v_item ->> 'target_type', btrim(v_item ->> 'target_id'));
    -- clock_timestamp, not now(): keeps the order the viewer wrote them in.
    insert into public.bold_predictions (post_id, author_id, body, target_type, target_id, created_at)
    values (p_post_id, auth.uid(), btrim(v_item ->> 'body'), v_item ->> 'target_type', btrim(v_item ->> 'target_id'), clock_timestamp());
  end loop;

  insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
  select p_post_id, auth.uid(), '', true
   where not exists (
     select 1 from public.prompt_comments
      where post_id = p_post_id and author_id = auth.uid() and posted_with_pick and parent_comment_id is null);
end;
$$;

-- Backfill: a take for every answer and every set of predictions that has none,
-- stamped with when the person answered so the lists keep their order.
insert into public.prompt_comments (post_id, author_id, body, posted_with_pick, created_at)
select a.post_id, a.profile_id, '', true, a.at
  from (
    select post_id, profile_id, min(created_at) as at from public.prompt_responses group by 1, 2
    union
    select post_id, author_id, min(created_at) from public.bold_predictions group by 1, 2
  ) a
 where not exists (
   select 1 from public.prompt_comments c
    where c.post_id = a.post_id and c.author_id = a.profile_id
      and c.posted_with_pick and c.parent_comment_id is null);
