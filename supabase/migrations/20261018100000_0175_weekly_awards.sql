-- Prompt types 5/7: Weekly Awards. An opinion-only post with six required
-- slots: biggest winner / biggest loser (teams), best game (a matchup from that
-- week's schedule) and offensive / defensive player of the week and LVP, which
-- are open player searches against the directory (0172).
--
-- A player slot has no pre-made options. The first respondent to pick a player
-- gets an option row created for them inside prompts.submit_response, keyed by
-- (slot, player id); later respondents reuse it. Responses, post_aggregates and
-- the reveal then work unchanged, because they only ever see option uuids.

-- ------------------------------------------------------------------- kind --

-- Weekly Awards is never graded, same guard as power_rankings (0114).
alter table public.prompt_posts
  add constraint prompt_posts_weekly_awards_opinion_check
    check (template_kind <> 'weekly_awards' or is_opinion);

-- ------------------------------------------------------- player slot flag --

-- A slot answered by searching the player directory rather than choosing from
-- its options.
alter table public.prompt_slots add column player_search boolean not null default false;

-- nflverse gsis id of the player an option was created for.
alter table public.prompt_slot_options add column player_id text;

-- One option per player per slot. This is what makes concurrent first picks of
-- the same player collapse to a single row (submit_response inserts with
-- ON CONFLICT against it).
create unique index prompt_slot_options_slot_player_unique
  on public.prompt_slot_options (slot_id, player_id)
  where player_id is not null;

-- --------------------------------------------------------------- create_post --

-- Same body as 0174's (game_pick_margin, itself 0119's plus option.margin), plus: a weekly_awards post is validated up front (opinion,
-- never auto-resolved, exactly the six slots in order), and `player_search` is
-- stored on the slot and allowed on weekly_awards only. The signature is
-- unchanged, so the existing grants still apply.
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
  v_pos          int;
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

  -- Weekly Awards: opinion only, six `pick` slots. Slots 1-2 offer all 32 teams,
  -- slot 3 at least one matchup, slots 4-6 are player searches with no options.
  if p_template_kind = 'weekly_awards' then
    for v_pos in 0..5 loop
      v_slot := p_slots -> v_pos;
      select count(*), count(distinct option ->> 'team_code')
        into v_option_count, v_team_count
        from jsonb_array_elements(coalesce(v_slot -> 'options', '[]'::jsonb)) option;
      if not p_is_opinion
         or p_resolution_source is not null
         or jsonb_array_length(p_slots) <> 6
         or v_slot ->> 'shape' <> 'pick'
         or (v_pos < 2 and (coalesce((v_slot ->> 'player_search')::boolean, false) or v_option_count <> 32 or v_team_count <> 32))
         or (v_pos = 2 and (coalesce((v_slot ->> 'player_search')::boolean, false) or v_option_count < 1))
         or (v_pos > 2 and (not coalesce((v_slot ->> 'player_search')::boolean, false) or v_option_count <> 0)) then
        raise exception 'invalid_weekly_awards' using errcode = '22023';
      end if;
    end loop;
  elsif exists (
    select 1 from jsonb_array_elements(p_slots) s where coalesce((s ->> 'player_search')::boolean, false)
  ) then
    raise exception 'invalid_weekly_awards' using errcode = '22023';
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
    insert into public.prompt_slots (post_id, label, shape, pick_count, points, sort_order, source_game_id, player_search)
    values (
      v_post_id,
      v_slot ->> 'label',
      v_slot ->> 'shape',
      coalesce((v_slot ->> 'pick_count')::smallint, case when v_slot ->> 'shape' = 'rank' then jsonb_array_length(coalesce(v_slot -> 'options', '[]'::jsonb))::smallint end),
      (v_slot ->> 'points')::smallint,
      v_idx,
      v_slot ->> 'source_game_id',
      coalesce((v_slot ->> 'player_search')::boolean, false)
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

-- ----------------------------------------------------------- submit_response --

-- Same as 0114's, except that on a player_search slot each choice is a player id
-- from the directory rather than an option uuid. The option for that player is
-- created here the first time anyone picks them in this slot. Two people picking
-- the same new player at once both run the INSERT ... ON CONFLICT DO NOTHING; the
-- unique index lets exactly one insert land, and the SELECT after it (a fresh
-- statement, so it sees the committed winner) returns the same row for both.
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

  if p_comment is not null and length(trim(p_comment)) > 0 then
    insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
    values (p_post_id, v_user, trim(p_comment), true);
  end if;
end;
$$;
