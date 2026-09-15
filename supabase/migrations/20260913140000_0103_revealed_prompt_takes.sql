-- Individual calls are deliberately private while a prompt is open. Once it
-- locks, a take card can safely show the author's complete ticket.
create function prompts.revealed_responses(p_post_id uuid)
returns table (profile_id uuid, slot_id uuid, chosen_option_ids uuid[])
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.prompt_posts
    where id = p_post_id
      and (lock_at <= now() or status = 'resolved')
  ) then
    raise exception 'picks_not_revealed' using errcode = '42501';
  end if;

  return query
    select r.profile_id, r.slot_id, r.chosen_option_ids
    from public.prompt_responses r
    where r.post_id = p_post_id;
end;
$$;

revoke all on function prompts.revealed_responses(uuid) from public, anon;
grant execute on function prompts.revealed_responses(uuid) to authenticated;
