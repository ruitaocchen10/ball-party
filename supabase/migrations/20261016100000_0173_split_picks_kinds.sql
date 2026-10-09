-- Prompt types 1/7: Game Picks and Weekly Picks are separate template kinds
-- again. 0100 folded both into `picks`; the composer now authors `game_pick`
-- (one game) and `weekly_picks` (a slate) directly and stops writing `picks`.
-- `picks` stays allowed so nothing that still inserts it breaks, but every
-- existing row is moved to `weekly_picks` below.
--
-- The constraint also admits `weekly_awards` (and the already-live
-- `bold_predictions`, 0171) so the later slices don't each need their own
-- constraint rewrite. `power_rankings` (0114) must stay in the list. The
-- bold_predictions opinion guard (0171) is a separate constraint and is
-- untouched here.

alter table public.prompt_posts
  drop constraint prompt_posts_template_kind_check,
  add constraint prompt_posts_template_kind_check
    check (template_kind in (
      'picks', 'game_pick', 'weekly_picks', 'weekly_awards', 'bold_predictions',
      'stat_leader', 'ranking', 'power_rankings', 'custom_multi'
    ));

-- Every `picks` post becomes a Weekly Picks post, including a single-slot one
-- (the agreed behaviour). Grading is unaffected: grade_due_game_picks (0117)
-- and per-slot grading already treat picks / game_pick / weekly_picks alike,
-- and this touches neither slots, answers nor resolution_source.
update public.prompt_posts
   set template_kind = 'weekly_picks', template_name = 'Weekly Picks'
 where template_kind = 'picks';

-- 0119's tick only queued a games.csv download for a locked `game_pick`, so a
-- locked weekly_picks post would wait up to an hour for the next schedule
-- refresh to be graded. With every old `picks` row now weekly_picks, cover all
-- three graded kinds. Otherwise identical to 0119.
create or replace function prompts_private.auto_resolve_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll     prompts_private.nflverse_poll;
  v_status   int;
  v_content  text;
  v_synced   timestamptz;
begin
  select * into v_poll from prompts_private.nflverse_poll where id;
  v_synced := v_poll.schedule_synced_at;

  if v_poll.request_id is not null then
    select r.status_code, r.content into v_status, v_content
      from net._http_response r
     where r.id = v_poll.request_id;

    if found and v_status = 200 then
      perform prompts_private.grade_due_game_picks(v_content);

      begin
        perform prompts_private.sync_nfl_games(v_content);
        v_synced := now();
        update prompts_private.nflverse_poll set schedule_synced_at = v_synced where id;
      exception when others then
        raise warning 'nfl_schedule_sync_failed sqlerrm=%', sqlerrm;
      end;
    end if;
  end if;

  if v_synced is null or v_synced < now() - interval '1 hour' or exists (
    select 1 from public.prompt_posts
     where status in ('open', 'locked') and lock_at <= now() and resolved_at is null
       and template_kind in ('picks', 'game_pick', 'weekly_picks') and resolution_source is not null
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

revoke all on function prompts_private.auto_resolve_tick() from public, anon, authenticated;
