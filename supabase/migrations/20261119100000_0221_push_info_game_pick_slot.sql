-- 0219's push_info looked for a game pick's game in the post's
-- resolution_source ->> 'game_id', but game picks keep it on their slot
-- (prompt_slots.source_game_id, 0097); resolution_source is only the rule and
-- provider. So no game was found and every game-pick push fell back to "New
-- prompt" plus the caption, with no week or points either. Read the slot first,
-- then the post, as do_resolve does (0117).

create or replace function private.push_info(p_row public.push_outbox)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts;
  v_game public.nfl_games;
  v_game_id text;
  v_week smallint;
begin
  if p_row.kind = 'new_prompt' then
    select * into v_post from public.prompt_posts where id = p_row.post_id;
    if not found then
      return null;
    end if;

    if v_post.template_kind = 'game_pick' then
      v_game_id := coalesce(
        (select s.source_game_id from public.prompt_slots s where s.post_id = v_post.id order by s.id limit 1),
        v_post.resolution_source ->> 'game_id');
      if v_game_id is not null then
        select * into v_game from public.nfl_games where id = v_game_id;
      end if;
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
