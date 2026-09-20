-- Tests for admin-chosen art candidates on a pick-one prompt (0119): a
-- stat_leader slot may mark up to four options with a cover_position 1..k, and
-- nothing else may carry one.

begin;
select plan(9);
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

-- One pick slot with six candidates; p_positions gives each candidate's
-- cover_position in order (null = not in the art).
create function tests.leader_slots(p_positions int[]) returns jsonb
language sql as $$
  select jsonb_build_array(jsonb_build_object(
    'label', 'Leader', 'shape', 'pick', 'points', 25,
    'options', (
      select jsonb_agg(jsonb_build_object('label', 'Player ' || i, 'sublabel', 'BUF', 'team_code', 'BUF', 'sort_order', i - 1, 'cover_position', p_positions[i]) order by i)
      from generate_series(1, cardinality(p_positions)) i
    )
  ));
$$;

select tests.act_as_prompts_admin();

insert into tests.fx (k, v)
select 'leader_post', prompts.create_post(
  'stat_leader', 'Pick one', 'cap', 'who leads?', 'crit', now() + interval '1 day',
  tests.leader_slots(array[null, 2, null, 1, 4, 3]::int[]), null::jsonb, false
);

select is((
  select array_agg(o.label order by o.cover_position)
  from public.prompt_slot_options o
  join public.prompt_slots s on s.id = o.slot_id
  where s.post_id = (select v from tests.fx where k = 'leader_post') and o.cover_position is not null
), array['Player 4', 'Player 2', 'Player 6', 'Player 5'], 'the art candidates are stored in the admin''s placement order');

select is((
  select count(*)::int from public.prompt_slot_options o
  join public.prompt_slots s on s.id = o.slot_id
  where s.post_id = (select v from tests.fx where k = 'leader_post')
), 6, 'every candidate is stored, in or out of the art');

select is((
  select count(*)::int from public.prompt_slot_options o
  join public.prompt_slots s on s.id = o.slot_id
  where s.post_id = (select v from tests.fx where k = 'leader_post') and o.cover_position is null
), 2, 'candidates outside the art carry no position');

select lives_ok(
  $$ select prompts.create_post('stat_leader', 'Pick one', 'cap', 'p', 'crit', now() + interval '1 day',
       tests.leader_slots(array[null, null, null, null, null]::int[]), null::jsonb, false) $$,
  'a pool with no art positions is fine — the art falls back to the first four');

select throws_ok(
  $$ select prompts.create_post('stat_leader', 'Pick one', 'cap', 'p', 'crit', now() + interval '1 day',
       tests.leader_slots(array[1, 2, 3, 4, 5, null]::int[]), null::jsonb, false) $$,
  '22023', 'invalid_cover_options', 'five art candidates is rejected');

select throws_ok(
  $$ select prompts.create_post('stat_leader', 'Pick one', 'cap', 'p', 'crit', now() + interval '1 day',
       tests.leader_slots(array[1, 1, 2, null, null, null]::int[]), null::jsonb, false) $$,
  '22023', 'invalid_cover_options', 'a repeated art position is rejected');

select throws_ok(
  $$ select prompts.create_post('stat_leader', 'Pick one', 'cap', 'p', 'crit', now() + interval '1 day',
       tests.leader_slots(array[1, 3, null, null, null, null]::int[]), null::jsonb, false) $$,
  '22023', 'invalid_cover_options', 'a gap in the art positions is rejected');

select throws_ok(
  $$ select prompts.create_post('custom_multi', 'Hot take', 'cap', 'p', 'crit', now() + interval '1 day',
       tests.leader_slots(array[1, 2, null]::int[]), null::jsonb, true) $$,
  '22023', 'invalid_cover_options', 'only a pick-one prompt can carry art positions');

-- The table's own check, exercised as its owner rather than through the RPC.
reset role;
select throws_ok(
  $$ update public.prompt_slot_options set cover_position = 5
       where id = (select id from public.prompt_slot_options limit 1) $$,
  '23514', null, 'the table itself refuses a position outside 1–4');

select * from finish();
rollback;
