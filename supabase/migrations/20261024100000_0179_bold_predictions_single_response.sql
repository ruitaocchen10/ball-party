-- Bold Predictions become one response, like every other prompt: the viewer
-- writes up to five predictions and submits them together, once. After that
-- the response cannot be edited, and submitting is what unlocks everyone
-- else's predictions (the same trade the pick prompts make) instead of
-- waiting for lock.
--
-- The rows stay one-per-prediction in public.bold_predictions; a response is
-- simply "this author has rows on this post". So the per-row add/edit/delete
-- RPCs of 0171 go away and a single submit takes their place.

drop function prompts.add_bold_prediction(uuid, text, text, text);
drop function prompts.edit_bold_prediction(uuid, text, text, text);
drop function prompts.delete_bold_prediction(uuid);

-- p_predictions: [{ "body": text, "target_type": text, "target_id": text }, ...]
-- One to five entries, all or nothing. A second submit is refused, which also
-- covers a double-click racing the first.
create function prompts.submit_bold_predictions(p_post_id uuid, p_predictions jsonb)
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
end;
$$;

revoke all on function prompts.submit_bold_predictions(uuid, jsonb) from public, anon;
grant execute on function prompts.submit_bold_predictions(uuid, jsonb) to authenticated;

-- Everyone's predictions once the post has locked, or once the caller has made
-- their own response; otherwise only the caller's own (none, before submitting).
-- A void post is not revealed early.
create or replace function prompts.bold_predictions_for_post(p_post_id uuid)
returns setof public.bold_predictions
language sql
security definer
set search_path = ''
stable
as $$
  select bp.*
    from public.bold_predictions bp
    join public.prompt_posts p on p.id = bp.post_id
   where bp.post_id = p_post_id
     and (
       bp.author_id = auth.uid()
       or p.lock_at <= now()
       or p.status in ('locked', 'resolved')
       or exists (
         select 1 from public.bold_predictions mine
          where mine.post_id = p_post_id and mine.author_id = auth.uid()
       )
     )
   order by bp.created_at, bp.id;
$$;
