-- Tests for the Game Picks / Weekly Picks split (0173): the kind constraint
-- admits the new kinds and still rejects unknown ones, the `picks` backfill
-- turns old posts into Weekly Picks without disturbing grading, and the
-- auto-resolve tick now watches all three graded kinds.
--
-- The backfill is a one-shot UPDATE inside the migration, which has already run
-- by the time pgTAP starts, so the test replays the same statement over
-- freshly inserted `picks` rows. Keep the two in step.

begin;
select plan(16);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$
  select email from auth.users where id = p_id;
$$;

create function tests.act_as_prompts_admin() returns void
language plpgsql as $$
declare
  v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(v_id))::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end $$;

create function tests.mk_post(p_kind text, p_name text, p_games text[]) returns uuid
language plpgsql as $$
declare
  v_slots jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'label', g, 'shape', 'pick', 'points', 10, 'source_game_id', g,
    'options', jsonb_build_array(
      jsonb_build_object('label', 'Away', 'team_code', 'AWY'),
      jsonb_build_object('label', 'Home', 'team_code', 'HOM')
    )
  ) order by ord)
  into v_slots
  from unnest(p_games) with ordinality as t (g, ord);

  return prompts.create_post(
    p_kind, p_name, 'cap', 'who wins', 'crit', now() - interval '1 hour', v_slots,
    jsonb_build_object('provider', 'nflverse', 'rule', 'winner')
  );
end $$;

create function tests.raw_post(p_kind text, p_opinion boolean default false) returns void
language sql as $$
  insert into public.prompt_posts (template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, is_opinion, cover_team_codes)
  values (p_kind, 'raw', (select v from tests.fx where k = 'admin'), 'c', 'p', 'r', now() + interval '1 day', p_opinion,
          case when p_kind = 'power_rankings' then array['BAL', 'GB', 'TB', 'KC', 'PHI', 'BUF'] end)
$$;

-- ------------------------------------------------------------ constraint --

select tests.act_as_admin();
select lives_ok($$ select tests.raw_post('game_pick') $$, 'game_pick is an allowed kind');
select lives_ok($$ select tests.raw_post('weekly_picks') $$, 'weekly_picks is an allowed kind');
select lives_ok($$ select tests.raw_post('weekly_awards', true) $$, 'weekly_awards is an allowed kind');
select lives_ok($$ select tests.raw_post('bold_predictions', true) $$, 'bold_predictions is still an allowed kind');
select lives_ok($$ select tests.raw_post('power_rankings', true) $$, 'power_rankings is still an allowed kind');
select lives_ok($$ select tests.raw_post('picks') $$, 'picks stays allowed so old rows remain valid');
select throws_ok($$ select tests.raw_post('stat_leaders') $$, '23514', null, 'an unknown kind is still rejected');

-- -------------------------------------------------------------- backfill --

select tests.act_as_prompts_admin();
insert into tests.fx (k, v) select 'old_week', tests.mk_post('picks', 'Picks', array['game-thursday', 'game-later']);
insert into tests.fx (k, v) select 'old_single', tests.mk_post('picks', 'Single game picks', array['game-thursday']);
insert into tests.fx (k, v) select 'game', tests.mk_post('game_pick', 'Game Picks', array['game-thursday']);

select tests.act_as_admin();
update public.prompt_posts
   set template_kind = 'weekly_picks', template_name = 'Weekly Picks'
 where template_kind = 'picks';

select is((select count(*)::int from public.prompt_posts where template_kind = 'picks'), 0,
  'no picks rows remain after the backfill');
select is((select template_kind || '/' || template_name from public.prompt_posts where id = (select v from tests.fx where k = 'old_week')),
  'weekly_picks/Weekly Picks', 'a multi-slot picks post becomes Weekly Picks');
select is((select template_kind || '/' || template_name from public.prompt_posts where id = (select v from tests.fx where k = 'old_single')),
  'weekly_picks/Weekly Picks', 'a single-slot picks post also becomes Weekly Picks');
select is((select template_kind || '/' || template_name from public.prompt_posts where id = (select v from tests.fx where k = 'game')),
  'game_pick/Game Picks', 'an existing game_pick post is left alone');
select is((select count(*)::int from public.prompt_slots where post_id in (select v from tests.fx where k in ('old_week', 'old_single'))),
  3, 'the backfill keeps every slot');

-- --------------------------------------------------------------- grading --

select prompts_private.grade_due_game_picks(
  'header,season,game_type,week,gameday,weekday,gametime,away_team,away_score,home_team,home_score,location,result' || E'\n'
  || 'game-thursday,2026,REG,2,2026-09-17,Thursday,20:15,AWY,27,HOM,20,Home,-7' || E'\n'
  || 'game-later,2026,REG,2,2026-09-21,Monday,20:15,AWY,10,HOM,17,Home,'
);

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'old_week')),
  'resolved', 'a backfilled multi-game post still auto-grades to resolved');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'old_single')),
  'resolved', 'a backfilled single-game post still auto-grades to resolved');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'game')),
  'resolved', 'a game_pick post still auto-grades');

-- The tick itself needs pg_net, so check its trigger condition by definition.
select matches(pg_get_functiondef('prompts_private.auto_resolve_tick()'::regprocedure),
  'template_kind in \(''picks'', ''game_pick'', ''weekly_picks''\)',
  'the tick queues a score download for a locked weekly_picks post, not just game_pick');

select * from finish();
rollback;
