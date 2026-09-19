-- Tests for admin-chosen Power Rankings cover art (0118): a Power Rankings
-- post carries exactly six distinct cover teams drawn from its own pool, and
-- no other template carries any.

begin;
select plan(7);
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

-- A full-league pool with synthetic codes T01..T32, in the shape create_post expects.
create function tests.power_slots() returns jsonb
language sql as $$
  select jsonb_build_array(jsonb_build_object(
    'label', 'NFL Power Rankings', 'shape', 'rank', 'pick_count', 32, 'points', 1,
    'options', (select jsonb_agg(jsonb_build_object('label', 'Team ' || i, 'team_code', 'T' || lpad(i::text, 2, '0'), 'sort_order', i)) from generate_series(1, 32) i)
  ));
$$;

select tests.act_as_prompts_admin();

insert into tests.fx (k, v)
select 'power_post', prompts.create_post(
  'power_rankings', 'Power rankings', 'cap', 'rank the league', 'crit',
  now() + interval '1 day', tests.power_slots(), null::jsonb, true,
  array['T05', 'T01', 'T09', 'T32', 'T14', 'T20']
);

select is((select cover_team_codes from public.prompt_posts where id = (select v from tests.fx where k = 'power_post')),
  array['T05', 'T01', 'T09', 'T32', 'T14', 'T20'], 'create_post stores the cover teams in the admin''s order');

select throws_ok(
  $$ select prompts.create_post('power_rankings', 'Power rankings', 'cap', 'p', 'crit', now() + interval '1 day', tests.power_slots(), null::jsonb, true) $$,
  '22023', 'invalid_cover_teams', 'a Power Rankings post without cover teams is rejected');

select throws_ok(
  $$ select prompts.create_post('power_rankings', 'Power rankings', 'cap', 'p', 'crit', now() + interval '1 day', tests.power_slots(), null::jsonb, true, array['T01', 'T02', 'T03', 'T04', 'T05']) $$,
  '22023', 'invalid_cover_teams', 'five cover teams is rejected');

select throws_ok(
  $$ select prompts.create_post('power_rankings', 'Power rankings', 'cap', 'p', 'crit', now() + interval '1 day', tests.power_slots(), null::jsonb, true, array['T01', 'T01', 'T03', 'T04', 'T05', 'T06']) $$,
  '22023', 'invalid_cover_teams', 'a repeated cover team is rejected');

select throws_ok(
  $$ select prompts.create_post('power_rankings', 'Power rankings', 'cap', 'p', 'crit', now() + interval '1 day', tests.power_slots(), null::jsonb, true, array['T01', 'T02', 'T03', 'T04', 'T05', 'ZZZ']) $$,
  '22023', 'invalid_cover_teams', 'a cover team outside the post''s pool is rejected');

select throws_ok(
  $$ select prompts.create_post('custom_multi', 'Hot take', 'cap', 'p', 'crit', now() + interval '1 day',
       jsonb_build_array(jsonb_build_object('label', 'Pick one', 'shape', 'pick', 'points', 15,
         'options', jsonb_build_array(jsonb_build_object('label', 'Team One'), jsonb_build_object('label', 'Team Two')))),
       null::jsonb, true, array['T01', 'T02', 'T03', 'T04', 'T05', 'T06']) $$,
  '22023', 'invalid_cover_teams', 'a non-Power-Rankings post cannot carry cover teams');

select is((select count(*)::int from public.prompt_posts where template_kind <> 'power_rankings' and cover_team_codes is not null),
  0, 'no other template stores cover teams');

select * from finish();
rollback;
