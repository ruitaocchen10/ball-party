begin;
select plan(3);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('weekly-admin'));
insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.weekly_email(p_id uuid) returns text language sql security definer as $$
  select email from auth.users where id = p_id;
$$;

create function tests.act_as_weekly_admin() returns void language plpgsql as $$
declare v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.weekly_email(v_id))::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function tests.weekly_schedule() returns text language sql as $$
  select string_agg(line, E'\n') from (values
    ('header,season,game_type,week,gameday,weekday,gametime,away_team,away_score,home_team,home_score,location,result'),
    ('week-one-a,2026,REG,1,2026-09-13,Sunday,13:00,AWY,21,HOM,17,Home,-4'),
    ('week-one-b,2026,REG,1,2026-09-13,Sunday,13:00,AAA,14,BBB,24,Home,10')
  ) as t(line)
$$;

select tests.act_as_weekly_admin();
insert into tests.fx (k, v)
select 'weekly_post', prompts.create_post(
  'picks', 'Picks', 'cap', 'Week 1 picks', 'crit', now() - interval '1 hour',
  jsonb_build_array(
    jsonb_build_object('label', 'Game A', 'shape', 'pick', 'points', 10, 'source_game_id', 'week-one-a',
      'options', jsonb_build_array(jsonb_build_object('label', 'Away', 'team_code', 'AWY'), jsonb_build_object('label', 'Home', 'team_code', 'HOM'))),
    jsonb_build_object('label', 'Game B', 'shape', 'pick', 'points', 10, 'source_game_id', 'week-one-b',
      'options', jsonb_build_array(jsonb_build_object('label', 'Away', 'team_code', 'AAA'), jsonb_build_object('label', 'Home', 'team_code', 'BBB')))
  ),
  jsonb_build_object('provider', 'nflverse', 'rule', 'winner')
);

select is(
  (select count(*) from public.prompt_slots where post_id = (select v from tests.fx where k = 'weekly_post') and source_game_id is not null),
  2::bigint, 'a set of picks retains each selected game identity on its slot'
);

select tests.act_as_admin();
select prompts_private.grade_due_game_picks(tests.weekly_schedule());

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'weekly_post')),
  'resolved', 'a set of picks resolves only after every selected game has a winner');
select is(
  (select count(*) from public.prompt_slots sl join public.prompt_slot_options so on so.id = any(sl.correct_option_ids)
   where sl.post_id = (select v from tests.fx where k = 'weekly_post') and so.team_code in ('AWY', 'BBB')),
  2::bigint, 'each pick slot is graded against its own game result'
);

select * from finish();
rollback;
