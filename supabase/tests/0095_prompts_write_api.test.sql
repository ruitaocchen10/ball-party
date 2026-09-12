-- Tests for the prompts write API (0094 schema, 0095 RPCs).
--
-- Four fixture posts, one per concern, rather than one post doing everything:
-- multi_post covers create_post's wiring plus the cross-slot exclusion
-- constraint, locked_post is only for lock enforcement, grading_post is only
-- for resolve_post's arithmetic across all three shapes, and void_post_fx is
-- only for the void path. Mixing these into one post makes failures harder to
-- read without buying anything back.

begin;
select plan(30);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('alice', tests.mkuser('alice'));
insert into tests.fx (k, v) values ('bob',   tests.mkuser('bob'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

-- tests.act_as (harness.psql) doesn't put an email in its synthetic JWT — no
-- existing test needs one. prompts_private.is_admin() specifically checks
-- auth.jwt()->>'email', so this feature needs its own variant. Scoped to
-- this file's transaction, not added to the shared harness.
-- security definer only for the auth.users read — set_config('role', ...)
-- has to run as the original caller, not as the definer-function's owner,
-- so the read and the role switch can't live in the same function.
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

-- ------------------------------------------------------------------ create_post --

select tests.act_as((select v from tests.fx where k = 'alice'));
select throws_ok(
  $$ select prompts.create_post('game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day', '[]'::jsonb) $$,
  '42501', 'not_authorized', 'a non-admin cannot create a post'
);

select tests.act_as_prompts_admin();

insert into tests.fx (k, v)
select 'multi_post', prompts.create_post(
  'custom_multi', 'Division + wildcard', 'cap', 'pick your teams', 'crit',
  now() + interval '1 day',
  jsonb_build_array(
    jsonb_build_object(
      'label', 'Division winner', 'shape', 'pick', 'points', 15,
      'options', jsonb_build_array(
        jsonb_build_object('label', 'Team One', 'team_code', 'ONE'),
        jsonb_build_object('label', 'Team Two', 'team_code', 'TWO')
      )
    ),
    jsonb_build_object(
      'label', 'Wildcard', 'shape', 'pick_set', 'pick_count', 1, 'points', 10,
      'excludes_slot_indexes', jsonb_build_array(0),
      'options', jsonb_build_array(
        jsonb_build_object('label', 'Team One', 'team_code', 'ONE'),
        jsonb_build_object('label', 'Team Two', 'team_code', 'TWO'),
        jsonb_build_object('label', 'Team Three', 'team_code', 'THREE')
      )
    )
  )
);

insert into tests.fx (k, v)
select 'slot_pick', id from public.prompt_slots where post_id = (select v from tests.fx where k = 'multi_post') and shape = 'pick';
insert into tests.fx (k, v)
select 'slot_set', id from public.prompt_slots where post_id = (select v from tests.fx where k = 'multi_post') and shape = 'pick_set';
insert into tests.fx (k, v)
select 'opt_pick_one', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'slot_pick') and team_code = 'ONE';
insert into tests.fx (k, v)
select 'opt_set_one', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'slot_set') and team_code = 'ONE';
insert into tests.fx (k, v)
select 'opt_set_three', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'slot_set') and team_code = 'THREE';

select is((select count(*)::int from public.prompt_slots where post_id = (select v from tests.fx where k = 'multi_post')),
  2, 'create_post wrote both slots');
select is((select count(*)::int from public.prompt_slot_options so join public.prompt_slots sl on sl.id = so.slot_id
  where sl.post_id = (select v from tests.fx where k = 'multi_post')),
  5, 'and every option across both slots');
select is((select excluded_slot_id from public.prompt_slot_exclusions where slot_id = (select v from tests.fx where k = 'slot_set')),
  (select v from tests.fx where k = 'slot_pick'), 'and the wildcard slot excludes the division-winner slot, resolved by index to id');

-- --------------------------------------------------------------- submit_response --

select tests.act_as((select v from tests.fx where k = 'alice'));

select throws_ok(
  format(
    $$ select prompts.submit_response(%L, jsonb_build_object(%L, jsonb_build_array(%L))) $$,
    (select v from tests.fx where k = 'multi_post'), (select v from tests.fx where k = 'slot_pick')::text, (select v from tests.fx where k = 'opt_pick_one')::text
  ),
  '22023', 'incomplete_slot', 'submitting only one of a post''s two slots is rejected'
);

select throws_ok(
  format(
    $$ select prompts.submit_response(%L, jsonb_build_object(%L, jsonb_build_array(%L), %L, jsonb_build_array(%L))) $$,
    (select v from tests.fx where k = 'multi_post'),
    (select v from tests.fx where k = 'slot_pick')::text, (select v from tests.fx where k = 'opt_pick_one')::text,
    (select v from tests.fx where k = 'slot_set')::text, (select v from tests.fx where k = 'opt_set_one')::text
  ),
  '22023', 'option_already_used', 'the wildcard slot cannot reuse the team already picked as division winner'
);

select lives_ok(
  format(
    $$ select prompts.submit_response(%L, jsonb_build_object(%L, jsonb_build_array(%L), %L, jsonb_build_array(%L)), 'book it') $$,
    (select v from tests.fx where k = 'multi_post'),
    (select v from tests.fx where k = 'slot_pick')::text, (select v from tests.fx where k = 'opt_pick_one')::text,
    (select v from tests.fx where k = 'slot_set')::text, (select v from tests.fx where k = 'opt_set_three')::text
  ),
  'a non-conflicting pick across both slots, with an attached take, succeeds'
);

select is((select count(*)::int from public.prompt_responses where post_id = (select v from tests.fx where k = 'multi_post') and profile_id = (select v from tests.fx where k = 'alice')),
  2, 'alice now has one response row per slot');
select is((select posted_with_pick from public.prompt_comments where post_id = (select v from tests.fx where k = 'multi_post') and author_id = (select v from tests.fx where k = 'alice')),
  true, 'her attached take is flagged as posted with the pick');

select tests.act_as((select v from tests.fx where k = 'bob'));
select is((select count(*)::int from public.prompt_responses where profile_id = (select v from tests.fx where k = 'alice')),
  0, 'another viewer cannot read alice''s response rows — own-row RLS, not just the UI, hides them');
select lives_ok(
  $$ select prompts.post_comment((select v from tests.fx where k = 'multi_post'), 'no shot') $$,
  'anyone signed in can reply on the thread without having answered'
);
select is((select posted_with_pick from public.prompt_comments where post_id = (select v from tests.fx where k = 'multi_post') and author_id = (select v from tests.fx where k = 'bob')),
  false, 'a thread reply is not flagged as posted with a pick');

select is((select pct::int from prompts.post_aggregates((select v from tests.fx where k = 'multi_post'))
  where option_id = (select v from tests.fx where k = 'opt_pick_one')),
  100, 'post_aggregates sees alice''s pick in the percentage even though bob cannot read her row directly');

-- ----------------------------------------------------------------- lock enforcement --

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'locked_post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() - interval '1 hour',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
  ))
);

select tests.act_as((select v from tests.fx where k = 'alice'));
select throws_ok(
  format(
    $$ select prompts.submit_response(%L, jsonb_build_object(%L, jsonb_build_array(%L))) $$,
    (select v from tests.fx where k = 'locked_post'),
    (select id::text from public.prompt_slots where post_id = (select v from tests.fx where k = 'locked_post')),
    (select id::text from public.prompt_slot_options where slot_id = (select id from public.prompt_slots where post_id = (select v from tests.fx where k = 'locked_post')) limit 1)
  ),
  '55000', 'post_locked', 'a post past its lock_at rejects a new response'
);

-- ------------------------------------------------------------------- resolve_post --

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'grading_post', prompts.create_post(
  'custom_multi', 'Grading', 'cap', 'grading', 'crit', now() + interval '1 day',
  jsonb_build_array(
    jsonb_build_object(
      'label', 'Winner', 'shape', 'pick', 'points', 10,
      'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
    ),
    jsonb_build_object(
      'label', 'Wildcards', 'shape', 'pick_set', 'pick_count', 3, 'points', 30,
      'options', jsonb_build_array(
        jsonb_build_object('label', 'A'), jsonb_build_object('label', 'B'),
        jsonb_build_object('label', 'C'), jsonb_build_object('label', 'D')
      )
    ),
    jsonb_build_object(
      'label', 'Ranking', 'shape', 'rank', 'points', 30,
      'options', jsonb_build_array(
        jsonb_build_object('label', 'X'), jsonb_build_object('label', 'Y'), jsonb_build_object('label', 'Z')
      )
    )
  )
);

insert into tests.fx (k, v) select 'g_pick', id from public.prompt_slots where post_id = (select v from tests.fx where k = 'grading_post') and shape = 'pick';
insert into tests.fx (k, v) select 'g_set', id from public.prompt_slots where post_id = (select v from tests.fx where k = 'grading_post') and shape = 'pick_set';
insert into tests.fx (k, v) select 'g_rank', id from public.prompt_slots where post_id = (select v from tests.fx where k = 'grading_post') and shape = 'rank';

insert into tests.fx (k, v) select 'g_pick_home', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_pick') and label = 'Home';
insert into tests.fx (k, v) select 'g_pick_away', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_pick') and label = 'Away';
insert into tests.fx (k, v) select 'g_set_a', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_set') and label = 'A';
insert into tests.fx (k, v) select 'g_set_b', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_set') and label = 'B';
insert into tests.fx (k, v) select 'g_set_c', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_set') and label = 'C';
insert into tests.fx (k, v) select 'g_set_d', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_set') and label = 'D';
insert into tests.fx (k, v) select 'g_rank_x', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_rank') and label = 'X';
insert into tests.fx (k, v) select 'g_rank_y', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_rank') and label = 'Y';
insert into tests.fx (k, v) select 'g_rank_z', id from public.prompt_slot_options where slot_id = (select v from tests.fx where k = 'g_rank') and label = 'Z';

-- Alice: wrong pick; 2 of 3 correct wildcards (A, B right, D wrong — misses
-- C); rank submitted X, Y, Z against a true order of Y, X, Z.
select tests.act_as((select v from tests.fx where k = 'alice'));
select prompts.submit_response(
  (select v from tests.fx where k = 'grading_post'),
  jsonb_build_object(
    (select v from tests.fx where k = 'g_pick')::text, jsonb_build_array((select v from tests.fx where k = 'g_pick_home')::text),
    (select v from tests.fx where k = 'g_set')::text, jsonb_build_array(
      (select v from tests.fx where k = 'g_set_a')::text, (select v from tests.fx where k = 'g_set_b')::text, (select v from tests.fx where k = 'g_set_d')::text
    ),
    (select v from tests.fx where k = 'g_rank')::text, jsonb_build_array(
      (select v from tests.fx where k = 'g_rank_x')::text, (select v from tests.fx where k = 'g_rank_y')::text, (select v from tests.fx where k = 'g_rank_z')::text
    )
  )
);

select throws_ok(
  format($$ select prompts.resolve_post(%L, '{}'::jsonb) $$, (select v from tests.fx where k = 'grading_post')),
  '42501', 'not_authorized', 'resolve_post rejects a non-admin caller'
);

select tests.act_as_prompts_admin();

-- Ground truth: winner is Away (alice picked Home — 0 of 10). Correct
-- wildcards are A, B, C (alice had A, B, D — 2 of 3 = 20 of 30, rounded).
-- True rank order is Y, X, Z (alice submitted X, Y, Z — only position 3 (Z)
-- matches — 1 of 3 = 10 of 30, rounded).
select prompts.resolve_post(
  (select v from tests.fx where k = 'grading_post'),
  jsonb_build_object(
    (select v from tests.fx where k = 'g_pick')::text, jsonb_build_array((select v from tests.fx where k = 'g_pick_away')::text),
    (select v from tests.fx where k = 'g_set')::text, jsonb_build_array(
      (select v from tests.fx where k = 'g_set_a')::text, (select v from tests.fx where k = 'g_set_b')::text, (select v from tests.fx where k = 'g_set_c')::text
    ),
    (select v from tests.fx where k = 'g_rank')::text, jsonb_build_array(
      (select v from tests.fx where k = 'g_rank_y')::text, (select v from tests.fx where k = 'g_rank_x')::text, (select v from tests.fx where k = 'g_rank_z')::text
    )
  )
);

-- Read alice's own graded rows as alice, not as admin: prompt_responses'
-- own-row RLS means admin's session can't see them via a plain select
-- either — that's the policy working, not a gap, and exactly why
-- prompts.post_aggregates exists as the sanctioned cross-profile view.
select tests.act_as((select v from tests.fx where k = 'alice'));

select is((select points_earned from public.prompt_responses where slot_id = (select v from tests.fx where k = 'g_pick') and profile_id = (select v from tests.fx where k = 'alice')),
  0::smallint, 'wrong pick scores 0 of 10');
select is((select points_earned from public.prompt_responses where slot_id = (select v from tests.fx where k = 'g_set') and profile_id = (select v from tests.fx where k = 'alice')),
  20::smallint, '2 of 3 correct wildcards scores 20 of 30');
select is((select points_earned from public.prompt_responses where slot_id = (select v from tests.fx where k = 'g_rank') and profile_id = (select v from tests.fx where k = 'alice')),
  10::smallint, '1 of 3 exact rank positions scores 10 of 30');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'grading_post')),
  'resolved', 'the post is marked resolved');
select isnt((select resolved_at from public.prompt_posts where id = (select v from tests.fx where k = 'grading_post')),
  null, 'and carries a resolved_at timestamp');
select is((select correct_option_ids from public.prompt_slots where id = (select v from tests.fx where k = 'g_pick')),
  array[(select v from tests.fx where k = 'g_pick_away')], 'resolve_post copies the answer onto prompt_slots — the reveal, readable without post_aggregates');

select tests.act_as_prompts_admin();
select throws_ok(
  format($$ select prompts.resolve_post(%L, '{}'::jsonb) $$, (select v from tests.fx where k = 'grading_post')),
  '55000', 'not_resolvable', 'a resolved post cannot be resolved again'
);

-- ----------------------------------------------------------------------- void_post --

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'void_post_fx', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'postponed?', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
  ))
);

select throws_ok(
  format($$ select prompts.void_post(%L, null) $$, (select v from tests.fx where k = 'void_post_fx')),
  '22023', 'reason_required', 'voiding without a reason is rejected'
);
select lives_ok(
  format($$ select prompts.void_post(%L, 'field unplayable') $$, (select v from tests.fx where k = 'void_post_fx')),
  'voiding with a reason succeeds'
);
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'void_post_fx')),
  'void', 'status is void');
select is((select void_reason from public.prompt_posts where id = (select v from tests.fx where k = 'void_post_fx')),
  'field unplayable', 'and the reason is recorded');

select tests.act_as((select v from tests.fx where k = 'alice'));
select throws_ok(
  format(
    $$ select prompts.submit_response(%L, jsonb_build_object(%L, jsonb_build_array(%L))) $$,
    (select v from tests.fx where k = 'void_post_fx'),
    (select id::text from public.prompt_slots where post_id = (select v from tests.fx where k = 'void_post_fx')),
    (select id::text from public.prompt_slot_options where slot_id = (select id from public.prompt_slots where post_id = (select v from tests.fx where k = 'void_post_fx')) limit 1)
  ),
  '55000', 'post_locked', 'a void post accepts no responses either'
);

-- -------------------------------------------------------------------- answer hiding --

-- Same shape as the auction's leak test (0010): a hidden answer must be
-- unreachable, not merely unrendered, and absent from the Realtime feed.
-- private.prompt_slot_answers has no grant at all to authenticated (not
-- "RLS hides the rows" — there's no privilege to even attempt the read), so
-- the failure mode is a permission error, not an empty result set.
select throws_ok(
  format($$ select count(*) from private.prompt_slot_answers where slot_id = %L $$, (select v from tests.fx where k = 'g_pick')),
  '42501', 'permission denied for table prompt_slot_answers',
  'even after resolution, an authenticated session cannot read the hidden answers table at all'
);

select tests.act_as_admin();
select is((select count(*)::int from private.prompt_slot_answers where slot_id = (select v from tests.fx where k = 'g_pick')),
  1, 'the answer really was written — just not reachable under RLS as a normal session');

select set_eq(
  $$ select schemaname || '.' || tablename from pg_publication_tables where pubname = 'supabase_realtime' and tablename like 'prompt_%' $$,
  $$ values ('public.prompt_posts'), ('public.prompt_slots'), ('public.prompt_slot_options'), ('public.prompt_slot_exclusions'), ('public.prompt_comments') $$,
  'prompt_responses is deliberately absent from the Realtime publication — see 0094'
);

select * from finish();
rollback;
