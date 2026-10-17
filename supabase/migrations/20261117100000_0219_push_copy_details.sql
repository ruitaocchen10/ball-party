-- Push alerts say more than "open the app" (0206 used fixed copy). The sender
-- builds the words in supabase/functions/send-push/payload.ts; this gives it the
-- facts, as `info` on each claimed push.
--
--   friend_request / take_reply / room_invite: the actor's name (the same one the
--     inbox shows) and, for a take_reply, how many replies are folded in.
--   new_prompt: the prompt's kind, week, lock time, and for a game pick the
--     matchup, kickoff and points.
--
-- Nothing here reaches a recipient who could not already see it: the actor is
-- the person behind an inbox item (a blocked actor's push is suppressed before
-- this runs), and a prompt is public. Take text is never included.

create function private.push_info(p_row public.push_outbox)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts;
  v_game public.nfl_games;
  v_week smallint;
begin
  if p_row.kind = 'new_prompt' then
    select * into v_post from public.prompt_posts where id = p_row.post_id;
    if not found then
      return null;
    end if;

    if v_post.template_kind = 'game_pick' and v_post.resolution_source ->> 'game_id' is not null then
      select * into v_game from public.nfl_games where id = v_post.resolution_source ->> 'game_id';
    end if;

    -- A weekly post belongs to the week of the first game at or after its lock
    -- (0171); the awards look back at the week just played.
    if v_post.template_kind = 'weekly_awards' then
      select week into v_week from public.nfl_games where kickoff < v_post.lock_at order by kickoff desc limit 1;
    elsif v_game.id is not null then
      v_week := v_game.week;
    else
      select week into v_week from public.nfl_games where kickoff >= v_post.lock_at order by kickoff limit 1;
    end if;

    return jsonb_strip_nulls(jsonb_build_object(
      'template_kind', v_post.template_kind,
      'caption',       v_post.caption,
      'lock_at',       v_post.lock_at,
      'week',          v_week,
      'away_team',     v_game.away_team,
      'home_team',     v_game.home_team,
      'kickoff',       v_game.kickoff,
      'primetime',     v_game.primetime,
      'points', case when v_game.id is not null
                     then (select s.points from public.prompt_slots s where s.post_id = v_post.id order by s.id limit 1) end
    ));
  end if;

  return (
    select jsonb_strip_nulls(jsonb_build_object(
      'actor_name',  coalesce(nullif(x.actor_display_name, ''), nullif(x.actor_username, '')),
      'reply_count', case when x.kind = 'take_reply' then x.reply_count end
    ))
      from private.inbox_items(p_row.recipient_id) x
     where x.item_key = p_row.item_key
  );
end;
$$;

revoke all on function private.push_info(public.push_outbox) from public, anon, authenticated;

-- Same as 0206's, plus `info`.
create or replace function public.claim_push_batch(p_limit integer default 50)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_row    public.push_outbox;
  v_why    text;
  v_result jsonb := '[]'::jsonb;
  v_devices jsonb;
begin
  update public.push_outbox
     set dead_at = now(), last_error = 'expired'
   where sent_at is null and dead_at is null
     and created_at < now() - interval '1 hour'
     and (claimed_at is null or claimed_at < now() - interval '2 minutes');

  for v_row in
    select * from public.push_outbox
     where sent_at is null and dead_at is null
       and available_at <= now()
       and (claimed_at is null or claimed_at < now() - interval '2 minutes')
     order by id
     limit greatest(1, least(coalesce(p_limit, 50), 200))
     for update skip locked
  loop
    v_why := private.push_suppression(v_row);
    if v_why is not null then
      update public.push_outbox set dead_at = now(), last_error = 'suppressed: ' || v_why where id = v_row.id;
      continue;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment)), '[]'::jsonb)
      into v_devices
      from public.device_tokens t where t.user_id = v_row.recipient_id;
    if jsonb_array_length(v_devices) = 0 then
      update public.push_outbox set dead_at = now(), last_error = 'no_devices' where id = v_row.id;
      continue;
    end if;

    update public.push_outbox set claimed_at = now(), attempts = attempts + 1 where id = v_row.id;
    v_result := v_result || jsonb_build_object(
      'id', v_row.id,
      'kind', v_row.kind,
      'item_key', v_row.item_key,
      'post_id', v_row.post_id,
      'badge', (select count(*)::integer from private.inbox_items(v_row.recipient_id) x where x.is_unread),
      'info', private.push_info(v_row),
      'devices', v_devices
    );
  end loop;
  return v_result;
end;
$$;
