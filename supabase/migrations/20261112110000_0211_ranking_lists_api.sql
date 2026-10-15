-- Ranking lists (2/3): the API, the update card and its friends-only reads.
--
-- save_ranking_list     the editor's write: a new version, capped, optionally
--                       published as an update card
-- get_ranking_lists     a player's lists (current version of each kind)
-- get_ranking_list      one list's whole history
-- ranking_list_prefill  the viewer's list mapped onto a ranking prompt's options
--
-- Edit rules (docs/architecture/ranking-lists.md):
--   * one saved edit per list per rolling 24 hours (prompt answers are exempt)
--   * a save within 10 minutes of the last edit replaces that version, unless
--     its update card already has a reply
--   * while a prompt for the list's kind is open, the list is edited through
--     the prompt, so a standalone save raises prompt_open

-- ------------------------------------------------------------------ helpers --

-- The signed-in, non-guest, non-deleted caller; raises otherwise.
create function private.ranking_viewer()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or (auth.jwt() ->> 'is_anonymous')::boolean is true
     or not exists (select 1 from public.profiles p where p.id = v_me and not p.is_guest and p.deleted_at is null) then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  return v_me;
end;
$$;

-- The profile behind a username, only when the viewer may open it.
create function private.ranking_resolve_profile(p_me uuid, p_username text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
    from public.profiles p
   where p_username ~ '^[A-Za-z0-9_]{3,20}$'
     and lower(p.username) = lower(p_username)
     and not p.is_guest and p.deleted_at is null
     and private.can_view_profile(p_me, p.id);
$$;

-- Update cards are friends-only. This is a public function (not private)
-- because the read policies below run as the querying role, signed out
-- included, and that role cannot call into the private schema.
create function public.can_see_ranking_update(p_author uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and (auth.uid() = p_author or private.are_friends(auth.uid(), p_author));
$$;

revoke all on function public.can_see_ranking_update(uuid) from public;
grant execute on function public.can_see_ranking_update(uuid) to anon, authenticated;

-- Creates the update card for a version: a locked, ungraded prompt_posts row
-- by the player, plus the player's take (the note, possibly empty) that
-- replies hang on.
create function private.ranking_create_update_post(p_version uuid, p_profile uuid, p_kind text, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_label text := (select label from public.ranking_list_kinds where id = p_kind);
  v_post uuid;
begin
  insert into public.prompt_posts
    (template_kind, template_name, author_id, caption, prompt_text, resolution_criteria,
     lock_at, status, is_opinion, ranking_kind)
  values
    ('ranking_update', v_label || ' update', p_profile, v_label || ' update', v_label || ' update',
     'Opinion only; not graded.', now(), 'locked', true, p_kind)
  returning id into v_post;

  insert into public.prompt_comments (post_id, author_id, body, posted_with_pick)
  values (v_post, p_profile, coalesce(p_note, ''), true);

  update public.ranking_list_versions set update_post_id = v_post where id = p_version;
  return v_post;
end;
$$;

revoke all on function private.ranking_viewer() from public, anon, authenticated;
revoke all on function private.ranking_resolve_profile(uuid, text) from public, anon, authenticated;
revoke all on function private.ranking_create_update_post(uuid, uuid, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------ friends-only --

-- Everything about the Huddle is publicly readable (0112) except update
-- cards. A comment is readable only when its post is, which the inner select
-- already enforces because it runs under the posts policy.
drop policy prompt_posts_select_public on public.prompt_posts;
create policy prompt_posts_select_public on public.prompt_posts
  for select to anon, authenticated using (
    template_kind <> 'ranking_update' or public.can_see_ranking_update(author_id)
  );

drop policy prompt_comments_select_public on public.prompt_comments;
create policy prompt_comments_select_public on public.prompt_comments
  for select to anon, authenticated using (
    exists (select 1 from public.prompt_posts p where p.id = prompt_comments.post_id)
  );

-- prompts.post_comment (0102) with one addition: a post the caller cannot see
-- is not found, so a stranger cannot reply to a friends-only update card.
create or replace function prompts.post_comment(p_post_id uuid, p_body text, p_parent_comment_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_id     uuid;
  v_parent public.prompt_comments;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.prompt_posts p
     where p.id = p_post_id
       and (p.template_kind <> 'ranking_update' or public.can_see_ranking_update(p.author_id))
  ) then
    raise exception 'post_not_found' using errcode = 'P0002';
  end if;

  if p_parent_comment_id is not null then
    select * into v_parent from public.prompt_comments where id = p_parent_comment_id;
    if not found or v_parent.post_id <> p_post_id then
      raise exception 'parent_not_found' using errcode = 'P0002';
    end if;
    -- One level only: a reply's own parent must be a top-level take, never
    -- another reply.
    if v_parent.parent_comment_id is not null then
      raise exception 'nested_reply' using errcode = '22023';
    end if;
  end if;

  insert into public.prompt_comments (post_id, author_id, body, posted_with_pick, parent_comment_id)
  values (p_post_id, v_user, trim(p_body), false, p_parent_comment_id)
  returning id into v_id;

  return v_id;
end;
$$;

-- --------------------------------------------------------------------- save --

create function public.save_ranking_list(
  p_kind    text,
  p_items   text[],
  p_note    text default null,
  p_publish boolean default false
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me      uuid := private.ranking_viewer();
  v_note    text := nullif(trim(coalesce(p_note, '')), '');
  v_open    uuid;
  v_list    uuid;
  v_current uuid;
  v_last    public.ranking_list_versions;
  v_version uuid;
  v_replace boolean := false;
begin
  if v_note is not null and char_length(v_note) > 280 then
    raise exception 'note_too_long' using errcode = '22023';
  end if;
  perform private.ranking_check_items(p_kind, p_items);

  -- A prompt for this kind is open: the list is edited through the prompt.
  select id into v_open from public.prompt_posts
   where ranking_kind = p_kind and template_kind <> 'ranking_update'
     and status = 'open' and now() < lock_at
   order by lock_at limit 1;
  if v_open is not null then
    raise exception 'prompt_open' using errcode = '55000', detail = v_open::text;
  end if;

  v_list := private.ranking_ensure_list(v_me, p_kind);
  select current_version_id into v_current from public.ranking_lists where id = v_list;
  if v_current is not null and private.ranking_items(v_current) = p_items then
    raise exception 'no_change' using errcode = '22023';
  end if;

  select * into v_last from public.ranking_list_versions
   where list_id = v_list and source = 'edit'
   order by version_no desc limit 1;

  if found then
    -- Typo grace: replace the player's own latest version, but only while it
    -- is still the current one and nobody has replied to its card.
    if v_last.created_at > now() - interval '10 minutes'
       and v_last.id = v_current
       and not (v_last.update_post_id is not null and exists (
             select 1 from public.prompt_comments c
              where c.post_id = v_last.update_post_id and c.parent_comment_id is not null)) then
      v_replace := true;
    elsif v_last.created_at > now() - interval '24 hours' then
      raise exception 'edit_limit' using errcode = '55000',
        detail = (v_last.created_at + interval '24 hours')::text;
    end if;
  end if;

  if v_replace then
    v_version := v_last.id;
    perform private.ranking_replace_items(v_version, p_kind, p_items);
    update public.ranking_list_versions
       set updated_at = now(), note = coalesce(v_note, note)
     where id = v_version;
    if v_note is not null and v_last.update_post_id is not null then
      update public.prompt_comments set body = v_note
       where post_id = v_last.update_post_id and parent_comment_id is null and author_id = v_me;
    end if;
  else
    v_version := private.ranking_new_version(v_list, 'edit', null, v_note);
    perform private.ranking_replace_items(v_version, p_kind, p_items);
  end if;

  if p_publish and not exists (
       select 1 from public.ranking_list_versions where id = v_version and update_post_id is not null) then
    perform private.ranking_create_update_post(v_version, v_me, p_kind, v_note);
  end if;

  return v_version;
end;
$$;

-- -------------------------------------------------------------------- reads --

-- A player's lists: the current version of each kind they have. Not found
-- (no rows) when the viewer may not open the profile, as get_profile (0186).
create function public.get_ranking_lists(p_username text)
returns table (
  kind          text,
  label         text,
  item_kind     text,
  version_id    uuid,
  version_no    integer,
  created_at    timestamptz,
  version_count integer,
  items         text[]
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me      uuid := private.ranking_viewer();
  v_profile uuid;
begin
  perform private.rate_limit_hit('get_ranking_lists', 120, interval '1 minute');
  v_profile := private.ranking_resolve_profile(v_me, p_username);
  if v_profile is null then
    return;
  end if;
  return query
    select l.kind, k.label, k.item_kind, v.id, v.version_no, v.created_at,
           (select count(*)::integer from public.ranking_list_versions x where x.list_id = l.id),
           private.ranking_items(v.id)
      from public.ranking_lists l
      join public.ranking_list_kinds k on k.id = l.kind
      join public.ranking_list_versions v on v.id = l.current_version_id
     where l.profile_id = v_profile
     order by k.id;
end;
$$;

-- One list's history, newest first. The note and update card are shown only
-- to the owner and their friends, like the card itself.
create function public.get_ranking_list(p_username text, p_kind text)
returns table (
  version_id     uuid,
  version_no     integer,
  source         text,
  post_id        uuid,
  update_post_id uuid,
  note           text,
  created_at     timestamptz,
  updated_at     timestamptz,
  is_current     boolean,
  items          text[]
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me      uuid := private.ranking_viewer();
  v_profile uuid;
  v_close   boolean;
begin
  perform private.rate_limit_hit('get_ranking_list', 120, interval '1 minute');
  v_profile := private.ranking_resolve_profile(v_me, p_username);
  if v_profile is null then
    return;
  end if;
  v_close := v_profile = v_me or private.are_friends(v_me, v_profile);
  return query
    select v.id, v.version_no, v.source, v.post_id,
           case when v_close then v.update_post_id end,
           case when v_close then v.note end,
           v.created_at, v.updated_at, v.id = l.current_version_id,
           private.ranking_items(v.id)
      from public.ranking_lists l
      join public.ranking_list_versions v on v.list_id = l.id
     where l.profile_id = v_profile and l.kind = p_kind
     order by v.version_no desc;
end;
$$;

-- The viewer's current list for a ranking prompt, mapped onto the prompt's
-- options so the ballot opens pre-filled. Items the prompt has no option for
-- are skipped; no rows when the prompt is not a ranking prompt or the viewer
-- has no list yet.
create function public.ranking_list_prefill(p_post_id uuid)
returns table (slot_id uuid, option_id uuid, place smallint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me   uuid := private.ranking_viewer();
  v_kind text;
begin
  select ranking_kind into v_kind from public.prompt_posts
   where id = p_post_id and template_kind <> 'ranking_update';
  if v_kind is null then
    return;
  end if;
  return query
    select s.id, o.id, i.place
      from public.ranking_lists l
      join public.ranking_list_items i on i.version_id = l.current_version_id
      join public.prompt_slots s on s.post_id = p_post_id and s.shape = 'rank'
      join public.prompt_slot_options o on o.slot_id = s.id
       and ((i.team_code is not null and o.team_code = i.team_code)
         or (i.player_id is not null and o.player_id = i.player_id))
     where l.profile_id = v_me and l.kind = v_kind
     order by i.place;
end;
$$;

revoke all on function public.save_ranking_list(text, text[], text, boolean) from public, anon;
revoke all on function public.get_ranking_lists(text) from public, anon;
revoke all on function public.get_ranking_list(text, text) from public, anon;
revoke all on function public.ranking_list_prefill(uuid) from public, anon;
grant execute on function public.save_ranking_list(text, text[], text, boolean) to authenticated;
grant execute on function public.get_ranking_lists(text) to authenticated;
grant execute on function public.get_ranking_list(text, text) to authenticated;
grant execute on function public.ranking_list_prefill(uuid) to authenticated;
