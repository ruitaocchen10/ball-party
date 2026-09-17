-- The Huddle is a public read surface. A browser without a Ball Party
-- account (or a temporary lobby session) may browse posts, their choices, and
-- the discussion; every write path remains account-only in its RPC body.

drop policy if exists prompt_posts_select_authenticated on public.prompt_posts;
create policy prompt_posts_select_public on public.prompt_posts
  for select to anon, authenticated using (true);

drop policy if exists prompt_slots_select_authenticated on public.prompt_slots;
create policy prompt_slots_select_public on public.prompt_slots
  for select to anon, authenticated using (true);

drop policy if exists prompt_slot_options_select_authenticated on public.prompt_slot_options;
create policy prompt_slot_options_select_public on public.prompt_slot_options
  for select to anon, authenticated using (true);

drop policy if exists prompt_slot_exclusions_select_authenticated on public.prompt_slot_exclusions;
create policy prompt_slot_exclusions_select_public on public.prompt_slot_exclusions
  for select to anon, authenticated using (true);

drop policy if exists prompt_comments_select_authenticated on public.prompt_comments;
create policy prompt_comments_select_public on public.prompt_comments
  for select to anon, authenticated using (true);

-- A feed card only needs the name attached to a prompt or comment. Profiles
-- intentionally contain only public player projection fields, and this
-- narrowly limits anonymous reads to people who have appeared in the Huddle.
create policy profiles_select_prompt_authors_public on public.profiles
  for select to anon, authenticated using (
    exists (select 1 from public.prompt_posts where author_id = profiles.id)
    or exists (select 1 from public.prompt_comments where author_id = profiles.id)
  );

-- The aggregate and revealed-ticket functions are security-definer read
-- models. The revealed-ticket function retains its post-state check so open
-- individual picks never leak.
grant execute on function prompts.post_aggregates(uuid) to anon;

create or replace function prompts.revealed_responses(p_post_id uuid)
returns table (profile_id uuid, slot_id uuid, chosen_option_ids uuid[])
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
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

grant execute on function prompts.revealed_responses(uuid) to anon;

