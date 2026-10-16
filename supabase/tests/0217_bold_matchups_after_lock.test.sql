-- Tests for 0217: a Bold Predictions matchup tag must be a game of the post's
-- week that has not kicked off at the post's lock time. The post opens on the
-- Saturday and locks at the first Sunday kickoff, so the Thursday game of its
-- week is already played and cannot be tagged.

begin;
select plan(4);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin')), ('alice', tests.mkuser('alice'));
insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$ select email from auth.users where id = p_id; $$;

create function tests.act_as_prompts_admin() returns void
language plpgsql as $$
declare
  v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(v_id))::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function tests.pred(p_type text, p_id text) returns jsonb
language sql immutable as $$
  select jsonb_build_array(jsonb_build_object('body', 'a bold call', 'target_type', p_type, 'target_id', p_id))
$$;

create function tests.fxv(p_k text) returns uuid language sql stable as $$ select v from tests.fx where k = p_k $$;

-- One week: Thursday played by the time the post locks (lock = Sunday).
delete from public.nfl_games;
insert into public.nfl_games (id, season, week, kickoff, away_team, home_team) values
  ('2026_05_BUF_KC',  2026, 5, now() + interval '1 day', 'BUF', 'KC'),
  ('2026_05_DAL_PHI', 2026, 5, now() + interval '4 days', 'DAL', 'PHI'),
  ('2026_05_SF_SEA',  2026, 5, now() + interval '5 days', 'SF', 'SEA'),
  ('2026_06_NYG_WAS', 2026, 6, now() + interval '11 days', 'NYG', 'WAS');

grant execute on all functions in schema tests to authenticated;

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'bold_predictions', 'Bold Predictions', 'cap', 'Make your boldest calls', 'Opinion only',
  now() + interval '4 days', '[]'::jsonb, null::jsonb, true
);

select tests.act_as(tests.fxv('alice'));
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, tests.pred('matchup', '2026_05_BUF_KC')) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'a game already played at the lock cannot be tagged'
);
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, tests.pred('matchup', '2026_06_NYG_WAS')) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'nor can a game of another week'
);
select lives_ok(
  format($$ select prompts.submit_bold_predictions(%L, tests.pred('matchup', '2026_05_SF_SEA')) $$, tests.fxv('post')),
  'a game of the week that kicks off after the lock can be'
);
select is(
  (select count(*)::int from public.bold_predictions where post_id = tests.fxv('post')), 1,
  'and only that prediction was kept'
);

select * from finish();
rollback;
