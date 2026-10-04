-- Tests for Bold Predictions (0171, reshaped by 0179): one all-or-nothing
-- submit of one to five predictions per author, body and target validation,
-- no edits after submitting, and the reveal — everyone's once the post locks,
-- or as soon as the viewer has submitted their own.

begin;
select plan(30);
\ir support/harness.psql

-- one prediction as a submit payload entry
create function tests.pred(p_body text, p_type text, p_id text) returns jsonb
language sql immutable as $$
  select jsonb_build_object('body', p_body, 'target_type', p_type, 'target_id', p_id)
$$;

select tests.act_as_admin();
insert into tests.fx (k, v) values
  ('admin', tests.mkuser('admin')),
  ('alice', tests.mkuser('alice')),
  ('bob', tests.mkuser('bob')),
  ('carol', tests.mkuser('carol')),
  ('dave', tests.mkuser('dave'));
insert into tests.fx (k, v) select 'guest', tests.mkguest('guest');

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

create function tests.act_as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end $$;

create function tests.fxv(p_k text) returns uuid
language sql stable as $$ select v from tests.fx where k = p_k $$;

-- The schedule is real data on a long-running local stack; this test must see
-- only its own games (the transaction rolls the delete back).
delete from public.nfl_games;

-- Week 5 is the post's week (first kickoff after lock_at); week 6 is not.
insert into public.nfl_games (id, season, week, kickoff, away_team, home_team) values
  ('2026_05_BUF_KC', 2026, 5, now() + interval '2 days', 'BUF', 'KC'),
  ('2026_06_SF_LA',  2026, 6, now() + interval '9 days', 'SF', 'LA');

-- ------------------------------------------------------------- the post --

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'bold_predictions', 'Bold Predictions', 'cap', 'Make your boldest calls', 'Opinion only',
  now() + interval '1 day', '[]'::jsonb, null::jsonb, true
);
insert into tests.fx (k, v)
select 'other_post', prompts.create_post(
  'custom_multi', 'Hot take', 'cap', 'q', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Pick one', 'shape', 'pick', 'points', 15,
    'options', jsonb_build_array(jsonb_build_object('label', 'A'), jsonb_build_object('label', 'B'))
  )),
  null::jsonb, true
);

select throws_ok(
  $$ select prompts.create_post('bold_predictions', 'Bold', 'cap', 'q', 'crit', now() + interval '1 day', '[]'::jsonb, null::jsonb, false) $$,
  '23514', null, 'a bold_predictions post must be an opinion post'
);

-- ------------------------------------------------------------ submitting --

select tests.act_as(tests.fxv('alice'));
select prompts.submit_bold_predictions(tests.fxv('post'), jsonb_build_array(
  tests.pred('Bills win the AFC', 'team', 'BUF'),
  tests.pred('Bills beat the Chiefs by 10', 'matchup', '2026_05_BUF_KC'),
  tests.pred('This QB throws for 400', 'player', '00-0033873')
));
select is((select count(*)::int from public.bold_predictions where post_id = tests.fxv('post')), 3,
  'a signed-in user submits several predictions as one response');
select is((select array_agg(body order by created_at, id) from prompts.my_bold_predictions(tests.fxv('post'))),
  array['Bills win the AFC', 'Bills beat the Chiefs by 10', 'This QB throws for 400'],
  'they keep the order they were written in');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('again', 'team', 'KC'))) $$, tests.fxv('post')),
  '23505', 'already_answered', 'a response cannot be submitted twice');
select hasnt_function('prompts', 'edit_bold_prediction', 'there is no edit once submitted');
select hasnt_function('prompts', 'delete_bold_prediction', 'there is no delete once submitted');
select hasnt_function('prompts', 'add_bold_prediction', 'predictions are no longer added one at a time');

-- ------------------------------------------------------- shape and cap --

select tests.act_as(tests.fxv('carol'));
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, '[]'::jsonb) $$, tests.fxv('post')),
  '22023', 'no_predictions', 'an empty response is rejected');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, (select jsonb_agg(tests.pred('p' || n, 'team', 'KC')) from generate_series(1, 6) n)) $$, tests.fxv('post')),
  '54000', 'too_many_predictions', 'six predictions are rejected');

-- ------------------------------------------------------- body validation --

select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('', 'team', 'KC'))) $$, tests.fxv('post')),
  '23514', null, 'an empty body is rejected');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('   ', 'team', 'KC'))) $$, tests.fxv('post')),
  '23514', null, 'a whitespace-only body is rejected');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred(%L, 'team', 'KC'))) $$, tests.fxv('post'), repeat('x', 281)),
  '23514', null, 'a body over 280 characters is rejected');

-- ----------------------------------------------------- target validation --

select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('x', 'matchup', '2026_06_SF_LA'))) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'a matchup from another week is rejected');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('x', 'matchup', 'no_such_game'))) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'an unknown matchup is rejected');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('x', 'team', 'XYZ'))) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'an unknown team code is rejected');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('x', 'player', ''))) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'an empty player id is rejected');
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('x', 'coach', 'abc'))) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'an unknown target type is rejected');

select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('fine', 'team', 'KC'), tests.pred('x', 'team', 'XYZ'))) $$, tests.fxv('post')),
  '22023', 'invalid_target', 'one bad prediction rejects the whole response');
select is((select count(*)::int from prompts.my_bold_predictions(tests.fxv('post'))), 0,
  'and nothing from it is saved');

-- -------------------------------------------------------------- the limits --

select tests.act_as(tests.fxv('dave'));
select lives_ok(
  format($$ select prompts.submit_bold_predictions(%L, (select jsonb_agg(tests.pred(repeat('x', 280), 'team', 'KC')) from generate_series(1, 5))) $$, tests.fxv('post')),
  'five predictions of exactly 280 characters are accepted');

select tests.act_as(tests.fxv('bob'));
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('x', 'team', 'DET'))) $$, tests.fxv('other_post')),
  '22023', 'not_bold_predictions', 'only a bold_predictions post takes predictions');
select lives_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('Bob''s call', 'team', 'DET'))) $$, tests.fxv('post')),
  'the cap is per author, not per post');

select tests.act_as_guest(tests.fxv('guest'));
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('x', 'team', 'DET'))) $$, tests.fxv('post')),
  '42501', 'not_authenticated', 'a guest cannot submit');

-- ------------------------------------------- the reveal, before lock --

select tests.act_as(tests.fxv('carol'));
select is((select count(*)::int from public.bold_predictions where author_id = tests.fxv('bob')), 0,
  'RLS hides another author''s rows from a direct table read');
select is((select count(*)::int from prompts.bold_predictions_for_post(tests.fxv('post'))), 0,
  'someone who has not submitted sees nobody''s predictions before lock');

select tests.act_as(tests.fxv('alice'));
select is((select count(*)::int from prompts.bold_predictions_for_post(tests.fxv('post'))), 9,
  'submitting unlocks everyone else''s predictions before lock');

select tests.act_as_anon();
select is((select count(*)::int from prompts.bold_predictions_for_post(tests.fxv('post'))), 0,
  'a signed-out visitor sees nothing before lock');

-- ------------------------------------------------------------ after lock --

select tests.act_as_admin();
update public.prompt_posts set lock_at = now() - interval '1 minute' where id = tests.fxv('post');

select tests.act_as(tests.fxv('carol'));
select throws_ok(
  format($$ select prompts.submit_bold_predictions(%L, jsonb_build_array(tests.pred('late', 'team', 'KC'))) $$, tests.fxv('post')),
  '55000', 'post_locked', 'submitting is blocked after lock');
select is((select count(*)::int from prompts.bold_predictions_for_post(tests.fxv('post'))), 9,
  'everyone''s predictions are visible once the post has locked');

select tests.act_as_anon();
select is((select count(*)::int from prompts.bold_predictions_for_post(tests.fxv('post'))), 9,
  'a signed-out visitor sees the full revealed set after lock');

select * from finish();
rollback;
