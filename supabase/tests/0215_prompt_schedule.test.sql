-- Tests for 0215: the admin prompt calendar (BPP-15). Pre-fill is idempotent,
-- a draft is invisible to players, a ready slot opens by itself at opens_at,
-- a slot that cannot open is flagged and not retried, and only admins can use
-- any of it.

begin;
select plan(44);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('alice', tests.mkuser('alice'));

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

-- The cadence needs a real week: games Thursday to Monday, with a London
-- game early on Sunday. The week starts on the first Thursday 4 to 10 days
-- from now, so every opening time falls inside the pre-fill horizon. The
-- played game is 10 days back so its own weekly awards (the Tuesday after,
-- locking Wednesday noon) have already locked whatever day the suite runs.
create function tests.base() returns date language sql stable as $$
  select d + ((4 - extract(dow from d)::int + 7) % 7)
    from (select (now() at time zone 'America/New_York')::date + 4 as d) x
$$;
create function tests.et(p_date date, p_time time) returns timestamptz language sql immutable as $$
  select (p_date + p_time) at time zone 'America/New_York'
$$;

delete from public.nfl_games;
insert into public.nfl_games (id, season, week, kickoff, away_team, home_team, primetime) values
  ('2026_05_BUF_KC',  2026, 5, tests.et(tests.base(),     '20:15'), 'BUF', 'KC',  true),
  ('2026_05_JAX_MIA', 2026, 5, tests.et(tests.base() + 3, '09:30'), 'JAX', 'MIA', false),
  ('2026_05_DAL_PHI', 2026, 5, tests.et(tests.base() + 3, '13:00'), 'DAL', 'PHI', false),
  ('2026_05_SF_SEA',  2026, 5, tests.et(tests.base() + 3, '20:20'), 'SF',  'SEA', true),
  ('2026_05_NYG_WAS', 2026, 5, tests.et(tests.base() + 4, '20:15'), 'NYG', 'WAS', true),
  ('2026_04_MIA_NE',  2026, 4, now() - interval '10 days',         'MIA', 'NE',  true),
  ('2026_09_SF_SEA',  2026, 9, now() + interval '40 days',         'SF',  'SEA', true);
delete from prompts_private.schedule_slots;

-- ---------------------------------------------------------------- pre-fill --

select is(prompts_private.schedule_prefill(), 7, 'pre-fill adds the primetime game slots plus the four recurring kinds');
select is(prompts_private.schedule_prefill(), 0, 'running it again adds nothing');
select is((select count(*)::int from prompts_private.schedule_slots where week = 9), 0, 'a week outside the horizon gets no slots');
select is((select count(*)::int from prompts_private.schedule_slots where game_id = '2026_04_MIA_NE'), 0, 'a game already played gets no slot');
select is(
  (select count(*)::int from prompts_private.schedule_slots where kind = 'game_pick' and game_id in ('2026_05_JAX_MIA', '2026_05_DAL_PHI')),
  0, 'only primetime games get a game-pick slot'
);
select results_eq(
  $$ select opens_at, lock_at from prompts_private.schedule_slots where game_id = '2026_05_BUF_KC' $$,
  $$ select tests.et(tests.base(), '12:00'), tests.et(tests.base(), '20:15') $$,
  'a game pick opens at noon Eastern on game day and locks at kickoff'
);
select results_eq(
  $$ select opens_at, lock_at from prompts_private.schedule_slots where kind = 'weekly_picks' $$,
  $$ select tests.et(tests.base() - 1, '12:00'), tests.et(tests.base(), '20:15') $$,
  'weekly picks open the Wednesday before at noon and lock at the first kickoff'
);
select results_eq(
  $$ select opens_at, lock_at from prompts_private.schedule_slots where kind = 'weekly_awards' $$,
  $$ select tests.et(tests.base() + 5, '12:00'), tests.et(tests.base() + 6, '12:00') $$,
  'weekly awards open the Tuesday after the last game at noon and lock the next noon'
);
select results_eq(
  $$ select opens_at, lock_at from prompts_private.schedule_slots where kind = 'power_rankings' $$,
  $$ select tests.et(tests.base() - 2, '12:00'), tests.et(tests.base() - 1, '12:00') $$,
  'power rankings open the Tuesday before at noon and lock the next noon'
);
select results_eq(
  $$ select opens_at, lock_at from prompts_private.schedule_slots where kind = 'bold_predictions' $$,
  $$ select tests.et(tests.base() + 2, '12:00'), tests.et(tests.base() + 3, '09:30') $$,
  'bold predictions open the Saturday at noon and lock at the first Sunday kickoff'
);

-- Reads of the private table go through this, as whoever is acting.
create function tests.slot(p_id uuid) returns jsonb
language sql security definer stable as $$
  select to_jsonb(v) || jsonb_build_object('payload', s.payload)
    from prompts_private.schedule_slot_view v join prompts_private.schedule_slots s using (id)
   where v.id = p_id;
$$;

create function tests.slot_id(p_kind text, p_game text default null) returns uuid
language sql security definer stable as $$
  select id from prompts_private.schedule_slots where kind = p_kind and game_id is not distinct from p_game;
$$;

create function tests.weekly_payload() returns jsonb language sql as $$
  select jsonb_build_object('post', jsonb_build_object(
    'p_template_kind', 'weekly_picks', 'p_template_name', 'Weekly picks', 'p_caption', 'Scheduled cap',
    'p_prompt_text', 'Who wins?', 'p_resolution_criteria', 'Opinion only', 'p_is_opinion', true,
    'p_slots', jsonb_build_array(jsonb_build_object(
      'label', 'Winner', 'shape', 'pick', 'points', 10,
      'options', jsonb_build_array(jsonb_build_object('label', 'Bills', 'team_code', 'BUF'), jsonb_build_object('label', 'Chiefs', 'team_code', 'KC'))))
  ));
$$;

insert into tests.fx (k, v) values
  ('picks', tests.slot_id('weekly_picks')),
  ('awards', tests.slot_id('weekly_awards')),
  ('game_a', tests.slot_id('game_pick', '2026_05_BUF_KC')),
  ('game_b', tests.slot_id('game_pick', '2026_05_SF_SEA'));

-- ------------------------------------------------------------------ access --

select ok(not has_table_privilege('authenticated', 'prompts_private.schedule_slots', 'select'), 'the table is not readable by players');
select tests.act_as((select v from tests.fx where k = 'alice'));
select throws_ok($$ select * from prompts.schedule_range(now() - interval '1 day', now() + interval '30 days') $$, '42501', 'not_authorized', 'a player cannot read the calendar');
select throws_ok($$ select prompts.schedule_prefill() $$, '42501', 'not_authorized', 'a player cannot pre-fill');
select throws_ok($$ select * from prompts.schedule_queue() $$, '42501', 'not_authorized', 'a player cannot read the queue');
select throws_ok(
  format($$ select prompts.schedule_save_draft(%L, '{"post":{}}'::jsonb, null, null) $$, (select v from tests.fx where k = 'picks')),
  '42501', 'not_authorized', 'a player cannot save a draft'
);

-- ------------------------------------------------------------- state machine --

select tests.act_as_admin();
update prompts_private.schedule_slots set opens_at = now() + interval '1 day' where id = (select v from tests.fx where k = 'game_a');
select tests.act_as_prompts_admin();
select is(jsonb_array_length(prompts.schedule_range(now() - interval '1 day', now() + interval '30 days')), 7, 'the range lists all seven slots');
select is(
  (select e ->> 'needs_attention' from jsonb_array_elements(prompts.schedule_range(now() - interval '1 day', now() + interval '30 days')) e where e ->> 'game_id' = '2026_05_BUF_KC'),
  'true', 'an empty game slot due tomorrow needs attention'
);
select is(
  (select e ->> 'needs_attention' from jsonb_array_elements(prompts.schedule_range(now() - interval '1 day', now() + interval '30 days')) e where e ->> 'game_id' = '2026_05_SF_SEA'),
  'false', 'one due in a week does not yet'
);
select matches(
  (select e ->> 'attention' from jsonb_array_elements(prompts.schedule_range(now() - interval '1 day', now() + interval '30 days')) e where e ->> 'game_id' = '2026_05_BUF_KC'),
  'No prompt written', 'and the flag names the missing step'
);

select is(
  jsonb_array_length(prompts.schedule_range(tests.et(tests.base() + 3, '00:00'), tests.et(tests.base() + 4, '00:00'))), 1,
  'a slot sits on the day it opens: Sunday has the Sunday-night game pick'
);

select throws_ok(
  format($$ select prompts.schedule_mark_ready(%L) $$, (select v from tests.fx where k = 'picks')),
  'P0002', 'slot_not_editable', 'an empty slot cannot be marked ready'
);


select prompts.schedule_save_draft(
  (select v from tests.fx where k = 'picks'), tests.weekly_payload(), null,
  (prompts.schedule_get((select v from tests.fx where k = 'picks')) ->> 'lock_at')::timestamptz
);
select is(prompts.schedule_get((select v from tests.fx where k = 'picks')) ->> 'state', 'draft', 'saving makes it a draft');
select throws_ok(
  format($$ select prompts.schedule_mark_ready(%L) $$, (select v from tests.fx where k = 'picks')),
  '22023', 'not_ready: No open time', 'a draft with no open time cannot be marked ready'
);

select tests.act_as((select v from tests.fx where k = 'alice'));
select is((select count(*)::int from public.prompt_posts where caption = 'Scheduled cap'), 0, 'a draft is invisible to players');

select tests.act_as_prompts_admin();
select prompts.schedule_save_draft(
  (select v from tests.fx where k = 'picks'), tests.weekly_payload(), now() + interval '1 hour',
  (prompts.schedule_get((select v from tests.fx where k = 'picks')) ->> 'lock_at')::timestamptz
);
select lives_ok(
  format($$ select prompts.schedule_mark_ready(%L) $$, (select v from tests.fx where k = 'picks')),
  'a complete draft can be marked ready'
);
select is(prompts.schedule_get((select v from tests.fx where k = 'picks')) ->> 'state', 'ready', 'and is then ready');
select prompts.schedule_unready((select v from tests.fx where k = 'picks'));
select is(prompts.schedule_get((select v from tests.fx where k = 'picks')) ->> 'state', 'draft', 'unready takes it back to draft');
select prompts.schedule_mark_ready((select v from tests.fx where k = 'picks'));

-- A game slot whose draft is about no game is not complete.
select prompts.schedule_save_draft(
  (select v from tests.fx where k = 'game_b'), tests.weekly_payload(), now() + interval '1 hour',
  (prompts.schedule_get((select v from tests.fx where k = 'game_b')) ->> 'lock_at')::timestamptz
);
select throws_ok(
  format($$ select prompts.schedule_mark_ready(%L) $$, (select v from tests.fx where k = 'game_b')),
  '22023', null, 'a game slot whose draft is another kind cannot be marked ready'
);
select prompts.schedule_clear((select v from tests.fx where k = 'game_b'));
select is(prompts.schedule_get((select v from tests.fx where k = 'game_b')) ->> 'state', 'empty', 'clearing empties the slot');

-- -------------------------------------------------------------------- tick --

select is(
  (select e ->> 'due_at' from jsonb_array_elements(prompts.schedule_range(now(), now() + interval '2 hours')) e where e ->> 'id' = (select v::text from tests.fx where k = 'picks')) is not null,
  true, 'once it has an open time it moves to that day'
);

select tests.act_as_admin();
select is(prompts_private.promote_scheduled_tick(), 0, 'nothing opens before its time');
select is((select count(*)::int from public.prompt_posts where caption = 'Scheduled cap'), 0, 'and no post exists yet');

update prompts_private.schedule_slots set opens_at = now() - interval '1 minute' where id = (select v from tests.fx where k = 'picks');
select is(prompts_private.promote_scheduled_tick(), 1, 'a ready slot past its time opens');
select is(
  (select p.status from public.prompt_posts p where p.id = (tests.slot((select v from tests.fx where k = 'picks')) ->> 'post_id')::uuid),
  'open', 'as an open post'
);
select is(tests.slot((select v from tests.fx where k = 'picks')) ->> 'state', 'published', 'and the slot is published');
select is(tests.slot((select v from tests.fx where k = 'picks')) ->> 'display_state', 'live', 'which the calendar shows as live');
select is(prompts_private.promote_scheduled_tick(), 0, 'it does not open twice');

-- A ready slot whose post create_post rejects goes back to draft, flagged.
update prompts_private.schedule_slots
   set state = 'ready', author_id = (select v from tests.fx where k = 'admin'),
       opens_at = now() - interval '1 minute',
       payload = jsonb_build_object('post', jsonb_build_object(
         'p_template_kind', 'weekly_awards', 'p_template_name', 'Weekly awards', 'p_caption', 'bad', 'p_prompt_text', 'x',
         'p_resolution_criteria', 'x', 'p_is_opinion', true, 'p_slots', '[]'::jsonb))
 where id = (select v from tests.fx where k = 'awards');
select is(prompts_private.promote_scheduled_tick(), 0, 'a slot create_post rejects does not open');
select is(tests.slot((select v from tests.fx where k = 'awards')) ->> 'state', 'draft', 'it returns to draft');
select matches(tests.slot((select v from tests.fx where k = 'awards')) ->> 'publish_error', 'invalid_weekly_awards', 'with the reason recorded');
select is((tests.slot((select v from tests.fx where k = 'awards')) ->> 'needs_attention')::boolean, true, 'and is flagged on the calendar');

-- A prompt published straight from Compose covers its slot.
select tests.act_as_prompts_admin();
select prompts.schedule_link_post(
  prompts.create_post('weekly_picks', 'Weekly picks', 'Compose cap', 'Who wins?', 'Opinion only', now() + interval '1 day',
    (tests.weekly_payload() -> 'post' -> 'p_slots'), null, true),
  'game_pick', 2026::smallint, 5::smallint, '2026_05_SF_SEA');
select tests.act_as_admin();
select is(tests.slot((select v from tests.fx where k = 'game_b')) ->> 'state', 'published', 'publishing from Compose covers the matching slot');

-- ------------------------------------------------------------------ digest --

select ok(
  public.claim_schedule_digest() -> 'recipients' ? (select lower(email) from auth.users where id = (select v from tests.fx where k = 'admin')),
  'the digest goes to every admin'
);
delete from prompts_private.schedule_slots;
select is(public.claim_schedule_digest(), null, 'and says nothing when there is nothing to say');

select * from finish();
rollback;
