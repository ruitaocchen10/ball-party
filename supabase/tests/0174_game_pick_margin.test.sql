-- Tests for Game Picks winner + margin (0174): the sweep derives the winning
-- one of four options from the final score (exactly 7 counts as 7+), a tied
-- game voids a game_pick post, and on a weekly slate a tie grades only its own
-- slot as no-contest so the rest of the slate resolves.

begin;
select plan(19);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('viewer', tests.mkuser('viewer'));

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

-- AWY is the away team, HOM the home team, in every game.
create function tests.schedule() returns text
language sql as $$
  select string_agg(line, E'\n') from (values
    ('header,season,game_type,week,gameday,weekday,gametime,away_team,away_score,home_team,home_score,location,result'),
    ('home-by-3,2026,REG,2,2026-09-20,Sunday,13:00,AWY,17,HOM,20,Home,3'),
    ('home-by-7,2026,REG,2,2026-09-20,Sunday,13:00,AWY,17,HOM,24,Home,7'),
    ('home-by-10,2026,REG,2,2026-09-20,Sunday,13:00,AWY,17,HOM,27,Home,10'),
    ('away-by-6,2026,REG,2,2026-09-20,Sunday,13:00,AWY,26,HOM,20,Home,-6'),
    ('away-by-14,2026,REG,2,2026-09-20,Sunday,13:00,AWY,34,HOM,20,Home,-14'),
    ('game-tie,2026,REG,2,2026-09-20,Sunday,13:00,AWY,24,HOM,24,Home,0'),
    ('game-unplayed,2026,REG,2,2026-09-21,Monday,20:15,AWY,,HOM,,Home,')
  ) as t(line)
$$;

create function tests.margin_options() returns jsonb
language sql as $$
  select jsonb_build_array(
    jsonb_build_object('label', 'Away by <7', 'sublabel', 'Wins by 1–6',        'team_code', 'AWY', 'margin', 'under_7'),
    jsonb_build_object('label', 'Away by 7+', 'sublabel', 'Wins by 7 or more',  'team_code', 'AWY', 'margin', '7_plus'),
    jsonb_build_object('label', 'Home by <7', 'sublabel', 'Wins by 1–6',        'team_code', 'HOM', 'margin', 'under_7'),
    jsonb_build_object('label', 'Home by 7+', 'sublabel', 'Wins by 7 or more',  'team_code', 'HOM', 'margin', '7_plus')
  )
$$;

-- A locked game_pick post (one four-option slot, 20 points) for one game.
create function tests.mk_game_pick(p_game text) returns uuid
language sql as $$
  select prompts.create_post(
    'game_pick', 'Game Picks', 'cap', 'who wins and by how much', 'crit', now() - interval '1 hour',
    jsonb_build_array(jsonb_build_object(
      'label', p_game, 'shape', 'pick', 'points', 20, 'source_game_id', p_game, 'options', tests.margin_options()
    )),
    jsonb_build_object('provider', 'nflverse', 'rule', 'winner')
  )
$$;

create function tests.opt(p_post uuid, p_team text, p_margin text) returns uuid
language sql as $$
  select o.id from public.prompt_slot_options o join public.prompt_slots s on s.id = o.slot_id
   where s.post_id = p_post and o.team_code = p_team and o.margin = p_margin
$$;

create function tests.pick(p_post uuid, p_team text, p_margin text) returns void
language sql as $$
  insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids)
  select p_post, s.id, (select v from tests.fx where k = 'viewer'), array[tests.opt(p_post, p_team, p_margin)]
    from public.prompt_slots s where s.post_id = p_post
$$;

create function tests.correct_of(p_post uuid) returns uuid
language sql as $$
  select correct_option_ids[1] from public.prompt_slots where post_id = p_post
$$;

-- ------------------------------------------------------------- fixtures --

select tests.act_as_prompts_admin();
insert into tests.fx (k, v) select 'h3',  tests.mk_game_pick('home-by-3');
insert into tests.fx (k, v) select 'h7',  tests.mk_game_pick('home-by-7');
insert into tests.fx (k, v) select 'h10', tests.mk_game_pick('home-by-10');
insert into tests.fx (k, v) select 'a6',  tests.mk_game_pick('away-by-6');
insert into tests.fx (k, v) select 'a14', tests.mk_game_pick('away-by-14');
insert into tests.fx (k, v) select 'tie', tests.mk_game_pick('game-tie');
insert into tests.fx (k, v) select 'wait', tests.mk_game_pick('game-unplayed');

select is(
  (select array_agg(o.margin order by o.sort_order) from public.prompt_slot_options o
     join public.prompt_slots s on s.id = o.slot_id where s.post_id = (select v from tests.fx where k = 'h3')),
  array['under_7', '7_plus', 'under_7', '7_plus'],
  'create_post stores each option''s margin bucket');
select is(
  (select points from public.prompt_slots where post_id = (select v from tests.fx where k = 'h3')),
  20::smallint, 'a game pick carries its editable points value (20 by default)');
select throws_ok(
  $$ select prompts.create_post('game_pick', 'Game Picks', 'c', 'p', 'c', now() + interval '1 day',
       '[{"label":"x","shape":"pick","points":20,"options":[{"label":"a","team_code":"AWY","margin":"by_a_mile"},{"label":"b","team_code":"HOM"}]}]'::jsonb) $$,
  '23514', null, 'an unknown margin bucket is rejected');

-- A weekly slate (winner-only slots) with a normal game and a tied one.
select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'week', prompts.create_post(
  'weekly_picks', 'Weekly Picks', 'cap', 'who wins', 'crit', now() - interval '1 hour',
  jsonb_build_array(
    jsonb_build_object('label', 'g1', 'shape', 'pick', 'points', 10, 'source_game_id', 'home-by-3', 'options',
      jsonb_build_array(jsonb_build_object('label', 'Away', 'team_code', 'AWY'), jsonb_build_object('label', 'Home', 'team_code', 'HOM'))),
    jsonb_build_object('label', 'g2', 'shape', 'pick', 'points', 10, 'source_game_id', 'game-tie', 'options',
      jsonb_build_array(jsonb_build_object('label', 'Away', 'team_code', 'AWY'), jsonb_build_object('label', 'Home', 'team_code', 'HOM')))
  ),
  jsonb_build_object('provider', 'nflverse', 'rule', 'winner'));

select tests.act_as_admin();
select tests.pick((select v from tests.fx where k = 'h3'),  'HOM', 'under_7');
select tests.pick((select v from tests.fx where k = 'h7'),  'HOM', 'under_7'); -- wrong bucket on purpose
select tests.pick((select v from tests.fx where k = 'h10'), 'HOM', '7_plus');
select tests.pick((select v from tests.fx where k = 'a6'),  'AWY', 'under_7');
select tests.pick((select v from tests.fx where k = 'a14'), 'HOM', '7_plus'); -- wrong team on purpose
select tests.pick((select v from tests.fx where k = 'tie'), 'HOM', '7_plus');
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids)
select s.post_id, s.id, (select v from tests.fx where k = 'viewer'),
       array[(select o.id from public.prompt_slot_options o where o.slot_id = s.id and o.team_code = 'HOM')]
  from public.prompt_slots s where s.post_id = (select v from tests.fx where k = 'week');

select prompts_private.grade_due_game_picks(tests.schedule());

-- ------------------------------------------------------------- grading --

select is(tests.correct_of((select v from tests.fx where k = 'h3')),
  tests.opt((select v from tests.fx where k = 'h3'), 'HOM', 'under_7'), 'home win by 3 → Home by <7');
select is(tests.correct_of((select v from tests.fx where k = 'h7')),
  tests.opt((select v from tests.fx where k = 'h7'), 'HOM', '7_plus'), 'home win by exactly 7 → Home by 7+');
select is(tests.correct_of((select v from tests.fx where k = 'h10')),
  tests.opt((select v from tests.fx where k = 'h10'), 'HOM', '7_plus'), 'home win by 10 → Home by 7+');
select is(tests.correct_of((select v from tests.fx where k = 'a6')),
  tests.opt((select v from tests.fx where k = 'a6'), 'AWY', 'under_7'), 'away win by 6 → Away by <7');
select is(tests.correct_of((select v from tests.fx where k = 'a14')),
  tests.opt((select v from tests.fx where k = 'a14'), 'AWY', '7_plus'), 'away win by 14 → Away by 7+');

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'h3')),
  'resolved', 'a graded game pick closes');
select is((select points_earned from public.prompt_responses where post_id = (select v from tests.fx where k = 'h3')),
  20::smallint, 'the right team and bucket earn the full 20');
select is((select points_earned from public.prompt_responses where post_id = (select v from tests.fx where k = 'h7')),
  0::smallint, 'right team, wrong margin bucket earns nothing');
select is((select points_earned from public.prompt_responses where post_id = (select v from tests.fx where k = 'a14')),
  0::smallint, 'wrong team earns nothing');

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'wait')),
  'open', 'a game with no final score stays open');

-- ----------------------------------------------------------------- ties --

select is((select status || ': ' || void_reason from public.prompt_posts where id = (select v from tests.fx where k = 'tie')),
  'void: Game ended in a tie', 'a tied game voids a game_pick post');
select is((select correct_option_ids from public.prompt_slots where post_id = (select v from tests.fx where k = 'tie')),
  null, 'and reveals no answer');

select is((select correct_option_ids from public.prompt_slots
            where post_id = (select v from tests.fx where k = 'week') and source_game_id = 'game-tie'),
  '{}'::uuid[], 'on a weekly slate a tied game''s slot is graded no-contest');
select is((select points_earned from public.prompt_responses r join public.prompt_slots s on s.id = r.slot_id
            where s.post_id = (select v from tests.fx where k = 'week') and s.source_game_id = 'game-tie'),
  0::smallint, 'a no-contest slot pays nobody');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'week')),
  'resolved', 'and the rest of the slate still resolves');
select is((select sum(points_earned)::int from public.prompt_responses where post_id = (select v from tests.fx where k = 'week')),
  10, 'the slate total counts only the contested slot');

select * from finish();
rollback;
