-- Tests for automatic resolution (0096): create_post's resolution_source,
-- and grade_due_game_picks's parsing/grading against a fabricated nflverse
-- CSV. Deliberately does NOT exercise auto_resolve_tick's own net.http_get
-- call — that would make this suite depend on live network access, which
-- pgTAP tests never should. grade_due_game_picks takes plain CSV text
-- precisely so its logic is testable without the fetch; a real fetch was
-- verified by hand against the live nflverse release while building this
-- migration, not by this file.

begin;
select plan(11);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

-- Same as 0095's own copy — each test file's transaction is isolated, so
-- this can't be shared from there.
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

-- A fabricated one-row "nflverse schedule" file — same column order as the
-- real release (game_id,season,game_type,week,gameday,weekday,gametime,
-- away_team,away_score,home_team,home_score,location,result), truncated
-- after the columns grade_due_game_picks actually reads. Three rows: one
-- final with a clear winner, one final tie, one not yet played.
create function tests.fake_schedule() returns text
language sql as $$
  select string_agg(line, E'\n') from (values
    ('header,season,game_type,week,gameday,weekday,gametime,away_team,away_score,home_team,home_score,location,result'),
    ('game-final-away-wins,2026,REG,1,2026-09-13,Sunday,13:00,AWY,27,HOM,20,Home,-7'),
    ('game-final-tie,2026,REG,1,2026-09-13,Sunday,13:00,AWY,24,HOM,24,Home,0'),
    ('game-not-played,2026,REG,2,2026-09-20,Sunday,13:00,AWY,,HOM,,Home,')
  ) as t(line)
$$;

-- ---------------------------------------------------------- create_post --

select tests.act_as_prompts_admin();

select throws_ok(
  $$ select prompts.create_post('game_pick', 'g', 'cap', 'p', 'crit', now() + interval '1 day', '[]'::jsonb,
       jsonb_build_object('provider', 'espn', 'rule', 'winner', 'game_id', 'x')) $$,
  '23514', null, 'a resolution_source from a provider other than nflverse is rejected by the check constraint'
);

select lives_ok(
  $$ select prompts.create_post('game_pick', 'g', 'cap', 'p', 'crit', now() + interval '1 day', '[]'::jsonb,
       jsonb_build_object('provider', 'nflverse', 'rule', 'winner')) $$,
  'a resolution_source without a post-level game_id is valid because game ids now live on winner slots'
);

insert into tests.fx (k, v)
select 'winner_post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() - interval '1 hour',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(
      jsonb_build_object('label', 'Away Team', 'team_code', 'AWY'),
      jsonb_build_object('label', 'Home Team', 'team_code', 'HOM')
    )
  )),
  jsonb_build_object('provider', 'nflverse', 'rule', 'winner', 'game_id', 'game-final-away-wins')
);

select isnt((select resolution_source from public.prompt_posts where id = (select v from tests.fx where k = 'winner_post')),
  null, 'create_post stores a well-formed resolution_source');

-- ------------------------------------------------------- grade_due_game_picks --

-- grade_due_game_picks lives in prompts_private, unreachable to
-- authenticated (see the do_resolve check at the end of this file) — call
-- it as the owning role, the same way harness fixtures reach into private
-- schemas elsewhere in this suite.
select tests.act_as_admin();
select prompts_private.grade_due_game_picks(tests.fake_schedule());

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'winner_post')),
  'resolved', 'a post whose game has a final score with a winner auto-resolves');
select is(
  (select so.team_code from public.prompt_slots sl
     join public.prompt_slot_options so on so.id = any (sl.correct_option_ids)
    where sl.post_id = (select v from tests.fx where k = 'winner_post')),
  'AWY', 'the away team is marked correct, matching the fabricated 27-20 away win'
);

-- Tie: no winner exists, so this must NOT be resolved — it should fall to
-- the manual-review queue rather than get graded with a fabricated answer.
-- Back to the admin JWT for create_post's own is_admin() check — act_as_admin
-- above switched to postgres and cleared request.jwt.claims entirely.
select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'tie_post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() - interval '1 hour',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(
      jsonb_build_object('label', 'Away Team', 'team_code', 'AWY'),
      jsonb_build_object('label', 'Home Team', 'team_code', 'HOM')
    )
  )),
  jsonb_build_object('provider', 'nflverse', 'rule', 'winner', 'game_id', 'game-final-tie')
);

-- Not yet played: scores are blank in the fabricated file.
insert into tests.fx (k, v)
select 'not_played_post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() - interval '1 hour',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(
      jsonb_build_object('label', 'Away Team', 'team_code', 'AWY'),
      jsonb_build_object('label', 'Home Team', 'team_code', 'HOM')
    )
  )),
  jsonb_build_object('provider', 'nflverse', 'rule', 'winner', 'game_id', 'game-not-played')
);

-- team_code mismatch: this post's options don't use the codes the
-- fabricated row actually has, standing in for e.g. "LA" vs nflverse's
-- "LAR" — must not crash the batch and must not falsely resolve.
insert into tests.fx (k, v)
select 'mismatched_post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() - interval '1 hour',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(
      jsonb_build_object('label', 'Away Team', 'team_code', 'WRONG_AWY'),
      jsonb_build_object('label', 'Home Team', 'team_code', 'WRONG_HOM')
    )
  )),
  jsonb_build_object('provider', 'nflverse', 'rule', 'winner', 'game_id', 'game-final-away-wins')
);

select tests.act_as_admin();
select lives_ok(
  $$ select prompts_private.grade_due_game_picks(tests.fake_schedule()) $$,
  'a batch with a tie, an unplayed game and a team_code mismatch alongside gradable posts does not error'
);

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'tie_post')),
  'open', 'a tied final score is left unresolved rather than guessing a winner');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'not_played_post')),
  'open', 'a game with no scores yet is left unresolved');
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'mismatched_post')),
  'open', 'a team_code that matches neither side of the real row is left for manual review, not force-resolved');

-- Re-running over an already-resolved post is a no-op, not an error — the
-- batch runs on a timer and will see winner_post again next tick.
select lives_ok(
  $$ select prompts_private.grade_due_game_picks(tests.fake_schedule()) $$,
  're-grading a batch that includes an already-resolved post does not error'
);

-- --------------------------------------------------------------- do_resolve --

-- Same shape as 0095's answer-hiding test: prompts_private isn't reachable
-- from PostgREST at all, so a signed-in session gets a permission error,
-- not merely a rejected admin check.
select tests.act_as((select v from tests.fx where k = 'admin'));
select throws_ok(
  format($$ select prompts_private.do_resolve(%L, '{}'::jsonb) $$, (select v from tests.fx where k = 'winner_post')),
  '42501', null, 'do_resolve is unreachable outside prompts_private — no grant exists for authenticated at all'
);

select * from finish();
rollback;
