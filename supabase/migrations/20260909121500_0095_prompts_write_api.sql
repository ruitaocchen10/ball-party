-- The write API for prompts: everything components/social-prototype/ fakes
-- through usePrototypeFeed's localStorage. Five entry points:
--
--   prompts.create_post(...)              admin: publish a new post
--   prompts.submit_response(...)          viewer: lock in a pick (+ optional take)
--   prompts.post_comment(...)             viewer: reply on the thread
--   prompts.resolve_post(...)             admin: grade and close a post
--   prompts.void_post(...)                admin: close with no grading
--
-- and one read helper:
--
--   prompts.post_aggregates(...)          "what percent picked each option"
--
-- Grading in resolve_post is a straight port of logic.ts's scoreSlot: `pick`
-- is all-or-nothing on the one chosen option, `pick_set` pays out
-- proportional to how many of the correct set were chosen, `rank` pays out
-- proportional to how many positions match exactly. Keeping the same rule in
-- two languages is the tradeoff of also keeping the client able to preview a
-- score before a response is graded server-side; if that preview turns out
-- not to be needed, scoreSlot can go and this becomes the only copy.

-- ------------------------------------------------------------ submit_response --

-- One call answers every slot on a post at once, matching PostAnswerScreen's
-- single "Lock in" for the whole card. p_choices is {slot_id: [option_id,
-- ...]}; order inside each array matters only for a `rank` slot.
create function prompts.submit_response(p_post_id uuid, p_choices jsonb, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user           uuid := auth.uid();
  v_post           public.prompt_posts;
  v_slot           record;
  v_option_ids     uuid[];
  v_expected_count int;
  v_option_total   int;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_post from public.prompt_posts where id = p_post_id for update;
  if not found then
    raise exception 'post_not_found' using errcode = 'P0002';
  end if;
  -- The authoritative lock check. lock_at on the row is what the UI renders
  -- a countdown from, but nothing about that column stops a write — this is
  -- what actually does.
  if v_post.status <> 'open' or now() >= v_post.lock_at then
    raise exception 'post_locked' using errcode = '55000';
  end if;

  -- Pass 1: validate and write one response row per slot the post defines.
  -- Cross-slot exclusions are deliberately NOT checked in this pass — see
  -- pass 2 below for why.
  for v_slot in select * from public.prompt_slots where post_id = p_post_id loop
    v_option_ids := array(
      select elem::uuid
      from jsonb_array_elements_text(coalesce(p_choices -> v_slot.id::text, '[]'::jsonb)) as elem
    );

    select count(*) into v_option_total from public.prompt_slot_options where slot_id = v_slot.id;

    v_expected_count := case v_slot.shape
      when 'pick'     then 1
      when 'pick_set' then v_slot.pick_count
      else v_option_total -- rank: every option, in order
    end;

    if coalesce(array_length(v_option_ids, 1), 0) <> v_expected_count
       or (select count(distinct x) from unnest(v_option_ids) x) <> v_expected_count
    then
      raise exception 'incomplete_slot' using errcode = '22023', detail = v_slot.id::text;
    end if;

    if exists (
      select 1 from unnest(v_option_ids) oid
      where not exists (
        select 1 from public.prompt_slot_options so where so.id = oid and so.slot_id = v_slot.id
      )
    ) then
      raise exception 'invalid_option' using errcode = '22023', detail = v_slot.id::text;
    end if;

    insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids)
    values (p_post_id, v_slot.id, v_user, v_option_ids)
    on conflict (slot_id, profile_id)
    do update set chosen_option_ids = excluded.chosen_option_ids;
  end loop;

  -- Pass 2: the preseason-picks constraint (excludesSlotIds) — a team
  -- already used in an excluded sibling slot can't be reused here. This has
  -- to run after every slot in the post has a row, not per-slot inside pass
  -- 1, because a slot can exclude a sibling that hasn't been written yet
  -- depending on iteration order (the wildcard slot excludes all four
  -- division slots, but nothing orders wildcards after divisions).
  --
  -- Compares team_code, not chosen_option_ids directly. Each slot's options
  -- are their own rows with their own generated ids — the division-winner
  -- slot's "Bills" row and the wildcard slot's "Bills" row never share a
  -- uuid, even though the prototype's mockData.ts models exactly this
  -- constraint by giving both the *same* option id (the team code, reused
  -- across slots). team_code is this schema's equivalent stable identity;
  -- an exclusion is meaningless between slots that aren't team-based, which
  -- team_code is null for, so those are correctly never flagged.
  if exists (
    select 1
    from public.prompt_slot_exclusions ex
    join public.prompt_responses mine
      on mine.slot_id = ex.slot_id and mine.profile_id = v_user
    join public.prompt_responses theirs
      on theirs.slot_id = ex.excluded_slot_id and theirs.profile_id = v_user
    join public.prompt_slot_options mine_opt on mine_opt.id = any (mine.chosen_option_ids)
    join public.prompt_slot_options their_opt on their_opt.id = any (theirs.chosen_option_ids)
    where mine.post_id = p_post_id
      and mine_opt.team_code is not null
      and mine_opt.team_code = their_opt.team_code
  ) then
    raise exception 'option_already_used' using errcode = '22023';
  end if;

  if p_comment is not null and length(trim(p_comment)) > 0 then
    insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
    values (p_post_id, v_user, trim(p_comment), true);
  end if;
end;
$$;

-- --------------------------------------------------------------- post_comment --

create function prompts.post_comment(p_post_id uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id   uuid;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (select 1 from public.prompt_posts where id = p_post_id) then
    raise exception 'post_not_found' using errcode = 'P0002';
  end if;

  insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
  values (p_post_id, v_user, trim(p_body), false)
  returning id into v_id;

  return v_id;
end;
$$;

-- ----------------------------------------------------------------- create_post --

-- p_slots shape (one entry per slot, in display order):
--   {
--     "label": text, "shape": "pick" | "pick_set" | "rank",
--     "pick_count": int|null, "points": int,
--     "excludes_slot_indexes": [int, ...],   -- 0-based indexes into p_slots
--     "options": [{"label": text, "sublabel": text|null,
--                  "team_code": text|null, "headshot_url": text|null}, ...]
--   }
-- Indexes rather than ids for excludes_slot_indexes because the admin
-- composer builds the whole post client-side before any slot has a real id
-- yet — same reason ComposerFields.tsx's builders key exclusions off the
-- sibling slot's position, not an id that doesn't exist until publish.
--
-- p_resolution_source, when given, is copied straight onto prompt_posts —
-- see that column's comment in 0094. Validated there by a check constraint,
-- not here, same division of labour as every other column this function
-- just passes through.
create function prompts.create_post(
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
    insert into public.prompt_slots (post_id, label, shape, pick_count, points, sort_order)
    values (
      v_post_id,
      v_slot ->> 'label',
      v_slot ->> 'shape',
      (v_slot ->> 'pick_count')::smallint,
      (v_slot ->> 'points')::smallint,
      v_idx
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

  -- Second pass: excludes_slot_indexes can only resolve to real ids once
  -- every slot above has one.
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

-- ---------------------------------------------------------------- resolve_post --

-- The grading itself, split out from prompts.resolve_post below so 0096's
-- auto_resolve_tick can call it too — an automatic grade and an admin's
-- manual grade are the same operation once an answer exists, they just
-- differ in who's allowed to call it and where the answer came from. No
-- admin check in here: prompts_private isn't reachable from PostgREST at
-- all (see 0094's schema revoke), so this function's only callers are
-- prompts.resolve_post (which checks is_admin() itself, below) and
-- prompts_private.auto_resolve_tick (0096, which computes p_answers off a
-- live score rather than trusting a caller-supplied one) — there is no
-- third path in that could skip authorization.
--
-- p_answers shape: {slot_id: [correct_option_id, ...]}, ordered for `rank`.
-- Every slot on the post must have an entry — a post resolves as a whole,
-- not slot by slot, so there's never a state where some of its slots show a
-- score and others don't.
create function prompts_private.do_resolve(p_post_id uuid, p_answers jsonb)
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

    -- The reveal: see 0094's comment on prompt_slots.correct_option_ids.
    -- Same statement that grades below, same transaction that flips the
    -- post to 'resolved' at the end of this function — there is no window
    -- where the answer is graded but not yet visible, or visible but not
    -- yet graded.
    update public.prompt_slots set correct_option_ids = v_correct where id = v_slot.id;

    -- Mirrors logic.ts's scoreSlot: pick is exact-match-or-nothing on the
    -- one chosen option; pick_set and rank pay out points * (matches /
    -- total), rounded — overlap count for pick_set, exact-position count
    -- for rank.
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

-- Admin-facing entry point: same errcodes and behavior as before this was
-- split, just delegating the grading itself to do_resolve above.
create function prompts.resolve_post(p_post_id uuid, p_answers jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  perform prompts_private.do_resolve(p_post_id, p_answers);
end;
$$;

-- ------------------------------------------------------------------- void_post --

create function prompts.void_post(p_post_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required' using errcode = '22023';
  end if;

  update public.prompt_posts
     set status = 'void', void_reason = trim(p_reason)
   where id = p_post_id
     and status in ('open', 'locked');

  if not found then
    raise exception 'not_voidable' using errcode = '55000';
  end if;
end;
$$;

-- --------------------------------------------------------------- post_aggregates --

-- "What percent of respondents picked each option," per slot on a post,
-- plus that slot's total respondent count (`total_responses`) — the feed's
-- "N responses" line, which otherwise has no way to read at all: it's a
-- count over prompt_responses, own-row-only RLS. security definer +
-- stable, same idiom as auction_state: deliberately bypasses that RLS to
-- compute something safe to return (rounded percentages and a count, never
-- a row) — this is the only sanctioned window onto what other people
-- picked; see 0094 for why the table itself isn't published to Realtime.
create function prompts.post_aggregates(p_post_id uuid)
returns table (slot_id uuid, option_id uuid, pct numeric, total_responses bigint)
language sql
security definer
set search_path = ''
stable
as $$
  select
    so.slot_id,
    so.id as option_id,
    case when totals.n > 0 then round(100.0 * coalesce(counts.n, 0) / totals.n, 0) else null end as pct,
    totals.n as total_responses
  from public.prompt_slot_options so
  join public.prompt_slots sl on sl.id = so.slot_id
  join lateral (
    select count(*) as n from public.prompt_responses r where r.slot_id = so.slot_id
  ) totals on true
  left join lateral (
    select count(*) as n
    from public.prompt_responses r
    where r.slot_id = so.slot_id and so.id = any (r.chosen_option_ids)
  ) counts on true
  where sl.post_id = p_post_id;
$$;

-- ------------------------------------------------------------------- grants --

revoke all on function prompts.submit_response(uuid, jsonb, text) from public, anon;
revoke all on function prompts.post_comment(uuid, text)           from public, anon;
revoke all on function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb) from public, anon;
revoke all on function prompts.resolve_post(uuid, jsonb)          from public, anon;
revoke all on function prompts.void_post(uuid, text)              from public, anon;
revoke all on function prompts.post_aggregates(uuid)              from public, anon;

-- do_resolve is prompts_private's, not prompts' — schema-level revokes in
-- 0094 already keep anon/authenticated out, but an explicit revoke here
-- matches this file's habit of never relying on just one layer.
revoke all on function prompts_private.do_resolve(uuid, jsonb) from public, anon, authenticated;

-- create_post/resolve_post/void_post are granted to every authenticated
-- user, same as place_bid is granted to every auction participant — the
-- is_admin() check inside each function body is what actually gates them,
-- not the grant. Consistent with this codebase never using grants for
-- authorization, only for reachability.
grant execute on function prompts.submit_response(uuid, jsonb, text) to authenticated;
grant execute on function prompts.post_comment(uuid, text)           to authenticated;
grant execute on function prompts.create_post(text, text, text, text, text, timestamptz, jsonb, jsonb) to authenticated;
grant execute on function prompts.resolve_post(uuid, jsonb)          to authenticated;
grant execute on function prompts.void_post(uuid, text)              to authenticated;
grant execute on function prompts.post_aggregates(uuid)              to authenticated;
