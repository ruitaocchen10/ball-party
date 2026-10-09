-- Admin hard delete for prompt posts. void_post (0095) closes a post but
-- leaves it, its responses and its comments in place; this removes the post
-- outright for the cases where it should not exist at all (a mistaken
-- post, a duplicate, content that shouldn't have been published).
--
-- Any status, with or without responses: an admin deleting a post with
-- answers on it has decided that already. Every child table (slots, slot
-- options, exclusions, responses, comments, bold predictions) references
-- prompt_posts / prompt_slots with on delete cascade, so one delete clears
-- them all. Points live on the responses, so deleting a resolved post
-- takes its points out of the standings with it.
--
-- Gated the same way as create/resolve/void: the is_admin() check in the
-- body is the authorization, the grant is only reachability.

create function prompts.delete_post(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  delete from public.prompt_posts where id = p_post_id;

  if not found then
    raise exception 'post_not_found' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function prompts.delete_post(uuid) from public, anon;
grant execute on function prompts.delete_post(uuid) to authenticated;
