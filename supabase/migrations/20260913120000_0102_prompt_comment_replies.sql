-- Threaded replies on a prompt's takes. Every comment so far (0094) has been
-- flat under its post; this lets a comment reply to another comment instead,
-- one level deep — a reply to a take, not a reply to a reply. That matches
-- the thread UI this powers: each take is a card with its own reply list,
-- not arbitrarily nested discussion.

alter table public.prompt_comments
  add column parent_comment_id uuid references public.prompt_comments (id) on delete cascade;

create index prompt_comments_parent_id on public.prompt_comments (parent_comment_id);

-- prompts.post_comment gains an optional parent. Dropped and recreated
-- rather than a bare create-or-replace: adding a parameter changes the
-- function's identity, so the old 2-arg overload would otherwise stick
-- around unused alongside this one.
drop function if exists prompts.post_comment(uuid, text);

create function prompts.post_comment(p_post_id uuid, p_body text, p_parent_comment_id uuid default null)
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

  if not exists (select 1 from public.prompt_posts where id = p_post_id) then
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

revoke all on function prompts.post_comment(uuid, text, uuid) from public, anon;
grant execute on function prompts.post_comment(uuid, text, uuid) to authenticated;
