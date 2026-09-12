-- A Picks prompt is one winner-pick module that may contain one game or a
-- selected set from a week. Keep the two former values readable so posts
-- created before this migration remain valid and automatically resolvable.

alter table public.prompt_posts
  drop constraint prompt_posts_template_kind_check,
  add constraint prompt_posts_template_kind_check
    check (template_kind in ('picks', 'game_pick', 'weekly_picks', 'stat_leader', 'ranking', 'custom_multi'));

create or replace function prompts_private.grade_due_game_picks(p_csv text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post          public.prompt_posts;
  v_slot          record;
  v_line          text;
  v_game_id       text;
  v_away_team     text;
  v_away_score    text;
  v_home_team     text;
  v_home_score    text;
  v_winner_code   text;
  v_winner_option uuid;
  v_answers       jsonb;
  v_incomplete    boolean;
begin
  for v_post in
    select * from public.prompt_posts
     where status in ('open', 'locked') and lock_at <= now() and resolved_at is null
       and template_kind in ('picks', 'game_pick', 'weekly_picks') and resolution_source is not null
  loop
    begin
      v_answers := '{}'::jsonb;
      v_incomplete := false;
      for v_slot in select * from public.prompt_slots where post_id = v_post.id loop
        v_game_id := coalesce(v_slot.source_game_id, v_post.resolution_source ->> 'game_id');
        if v_game_id is null then v_incomplete := true; exit; end if;
        select l into v_line from unnest(string_to_array(p_csv, E'\n')) as l where l like v_game_id || ',%' limit 1;
        if v_line is null then v_incomplete := true; exit; end if;
        v_away_team := split_part(v_line, ',', 8);
        v_away_score := split_part(v_line, ',', 9);
        v_home_team := split_part(v_line, ',', 10);
        v_home_score := split_part(v_line, ',', 11);
        if v_away_score = '' or v_home_score = '' or v_away_score = v_home_score then v_incomplete := true; exit; end if;
        v_winner_code := case when v_home_score::int > v_away_score::int then v_home_team else v_away_team end;
        select id into v_winner_option from public.prompt_slot_options where slot_id = v_slot.id and team_code = v_winner_code;
        if v_winner_option is null then v_incomplete := true; exit; end if;
        v_answers := v_answers || jsonb_build_object(v_slot.id::text, jsonb_build_array(v_winner_option::text));
      end loop;
      if not v_incomplete then perform prompts_private.do_resolve(v_post.id, v_answers); end if;
    exception when others then
      raise warning 'auto_resolve_failed post_id=% sqlerrm=%', v_post.id, sqlerrm;
    end;
  end loop;
end;
$$;

create or replace function prompts_private.auto_resolve_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll    prompts_private.nflverse_poll;
  v_status  int;
  v_content text;
begin
  select * into v_poll from prompts_private.nflverse_poll where id;

  if v_poll.request_id is not null then
    select r.status_code, r.content into v_status, v_content
      from net._http_response r
     where r.id = v_poll.request_id;

    if found and v_status = 200 then
      perform prompts_private.grade_due_game_picks(v_content);
    end if;
  end if;

  if exists (
    select 1 from public.prompt_posts
     where status in ('open', 'locked') and lock_at <= now() and resolved_at is null
       and template_kind in ('picks', 'game_pick', 'weekly_picks')
       and resolution_source is not null
  ) then
    update prompts_private.nflverse_poll
       set request_id = net.http_get(
             url := 'https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv',
             timeout_milliseconds := 20000
           ),
           requested_at = now()
     where id;
  else
    update prompts_private.nflverse_poll set request_id = null, requested_at = null where id;
  end if;
end;
$$;
