-- Tests for the Bold Predictions read helpers (0174): the player lookup returns
-- identity fields for known ids to anyone, and the count RPC reports totals
-- (never text) for posts regardless of lock.

begin;
select plan(6);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values
  ('admin', tests.mkuser('admin')),
  ('alice', tests.mkuser('alice')),
  ('bob', tests.mkuser('bob'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.fxv(p_k text) returns uuid
language sql stable as $$ select v from tests.fx where k = p_k $$;

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

create function tests.act_as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end $$;

insert into prompts_private.nfl_players (player_id, display_name, search_name, position, team, headshot_url, status, season)
values
  ('test-0033873', 'Patrick Mahomes', 'patrick mahomes', 'QB', 'KC', 'https://img/mahomes.png', 'ACT', 2026),
  ('test-0035710', 'Nick Bosa', 'nick bosa', 'DL', 'SF', null, 'RES', 2026);

select tests.act_as_anon();
select is(
  (select count(*)::int from prompts.players_by_ids(array['test-0033873', 'test-0035710', 'nope'])),
  2, 'anon can look up players by id; unknown ids are simply absent');
select is(
  (select display_name || ' ' || team from prompts.players_by_ids(array['test-0033873'])),
  'Patrick Mahomes KC', 'the lookup returns name and team');
select is(
  (select count(*)::int from prompts.players_by_ids(array[]::text[])),
  0, 'an empty id list returns nothing');

-- Two authors, three predictions, on an open post.
select tests.act_as_admin();
insert into public.nfl_games (id, season, week, kickoff, away_team, home_team)
values ('2026_05_BUF_KC', 2026, 5, now() + interval '2 days', 'BUF', 'KC');
select tests.act_as_prompts_admin();

insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'bold_predictions', 'Bold Predictions', 'cap', 'Week 5 Bold Predictions', 'Opinion only',
  now() + interval '1 day', '[]'::jsonb, null::jsonb, true
);

select tests.act_as(tests.fxv('alice'));
select prompts.submit_bold_predictions(tests.fxv('post'), '[
  {"body": "one", "target_type": "team", "target_id": "BUF"},
  {"body": "two", "target_type": "team", "target_id": "KC"}
]'::jsonb);
select tests.act_as(tests.fxv('bob'));
select prompts.submit_bold_predictions(tests.fxv('post'), '[
  {"body": "three", "target_type": "team", "target_id": "GB"}
]'::jsonb);

select tests.act_as_anon();
select is(
  (select prediction_count from prompts.bold_prediction_counts(array[tests.fxv('post')])),
  3::bigint, 'anon sees the prediction count of an open post');
select is(
  (select author_count from prompts.bold_prediction_counts(array[tests.fxv('post')])),
  2::bigint, 'and how many people have written one');
select is(
  (select count(*)::int from prompts.bold_prediction_counts(array[gen_random_uuid()])),
  0, 'a post with no predictions has no row');

select * from finish();
rollback;
