-- Local development only. Never applied to a deployed environment: `db reset`
-- runs this after the migrations, and nothing else does.
--
-- The hosted project grants every table in `public` to anon and authenticated
-- by default, leaving RLS as the only gate. A local CLI stack no longer sets
-- those default privileges, so without this the app and the tests would hit
-- "permission denied" locally for tables that work fine in production — a
-- difference in environment defaults masquerading as a bug in the code.
--
-- SELECT only. The app never writes through PostgREST: every mutation goes
-- through a `security definer` RPC, so the write half of the hosted grant is
-- surface this does not need to reproduce.
grant select on all tables in schema public to anon, authenticated;

-- Social prompt gallery -------------------------------------------------------
--
-- A local-only gallery for exercising every prompt-card template and lifecycle
-- treatment at /social. Sign in as `demo@ballparty.local` with password
-- `ball-party-demo` after `supabase db reset`. The demo reader has responses
-- on the cards where a personal result is meaningful; the second respondent
-- makes the aggregate bars non-trivial.
--
-- These fixed ids make the rows easy to inspect in Studio. Keep the gallery
-- atomic: a schema mismatch must never leave a partially seeded local stack.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data
)
values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo@ballparty.local', crypt('ball-party-demo', gen_salt('bf')), now(), now() - interval '7 days', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Demo Reader"}'),
  ('00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'curator@ballparty.local', crypt('ball-party-demo', gen_salt('bf')), now(), now() - interval '7 days', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Ball Curator"}'),
  ('00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tasha@ballparty.local', crypt('ball-party-demo', gen_salt('bf')), now(), now() - interval '7 days', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Tasha"}');

insert into public.prompt_posts (
  id, template_kind, template_name, author_id, caption, prompt_text,
  resolution_criteria, lock_at, status, void_reason, created_at, resolved_at
)
values
  -- Open + unanswered: the CTA and dedicated single-game pick screen.
  ('00000000-0000-0000-0000-00000000a001', 'picks', 'Single game picks', '00000000-0000-0000-0000-00000000d002', 'Sunday night, no hedging.', 'Who wins Chiefs @ Bills?', 'The winner is the team with more points at final whistle.', now() + interval '3 days', 'open', null, now() - interval '20 minutes', null),
  -- Locked: compact weekly ticket, personal calls, and community breakdown.
  ('00000000-0000-0000-0000-00000000a002', 'weekly_picks', 'Weekly picks', '00000000-0000-0000-0000-00000000d002', 'Three games. One clean ticket.', 'Week 2 picks', 'Each game resolves from its final score.', now() - interval '2 hours', 'locked', null, now() - interval '2 days', null),
  -- Open + answered: generic card result mode before the answer is known.
  ('00000000-0000-0000-0000-00000000a003', 'stat_leader', 'Stat leader', '00000000-0000-0000-0000-00000000d002', 'Settle the Sunday argument early.', 'Who leads the league in rushing yards?', 'Official regular-season rushing-yard total after Week 18.', now() + interval '10 days', 'open', null, now() - interval '3 hours', null),
  -- Resolved rank: partial-credit order, correct/wrong rows, and scoremark.
  ('00000000-0000-0000-0000-00000000a004', 'ranking', 'Top-three ranking', '00000000-0000-0000-0000-00000000d002', 'Rank the three offenses you trust most.', 'Rank these offenses', 'The editorial panel publishes its Week 1 power ranking.', now() - interval '5 days', 'resolved', null, now() - interval '8 days', now() - interval '4 days'),
  -- Resolved custom multi: pick, pick-set and cross-slot result faces.
  ('00000000-0000-0000-0000-00000000a005', 'custom_multi', 'Preseason calls', '00000000-0000-0000-0000-00000000d002', 'A division winner and two wild cards — no duplicates.', 'Build your AFC playoff picture', 'The post resolves against the final AFC playoff field.', now() - interval '12 days', 'resolved', null, now() - interval '20 days', now() - interval '11 days'),
  -- Void: the stopped-card treatment and reason copy.
  ('00000000-0000-0000-0000-00000000a006', 'game_pick', 'Single game picks (legacy)', '00000000-0000-0000-0000-00000000d002', 'The game moved; this one is off the board.', 'Who wins Patriots @ Seahawks?', 'The winner is the team with more points at final whistle.', now() - interval '1 day', 'void', 'Game was postponed before kickoff.', now() - interval '4 days', null);

insert into public.prompt_slots (id, post_id, label, shape, pick_count, points, sort_order, correct_option_ids)
values
  ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-00000000a001', 'Chiefs @ Bills', 'pick', null, 10, 0, null),
  ('00000000-0000-0000-0000-00000000b201', '00000000-0000-0000-0000-00000000a002', 'Ravens @ Bengals', 'pick', null, 10, 0, null),
  ('00000000-0000-0000-0000-00000000b202', '00000000-0000-0000-0000-00000000a002', 'Cowboys @ Eagles', 'pick', null, 10, 1, null),
  ('00000000-0000-0000-0000-00000000b203', '00000000-0000-0000-0000-00000000a002', 'Broncos @ Chargers', 'pick', null, 10, 2, null),
  ('00000000-0000-0000-0000-00000000b301', '00000000-0000-0000-0000-00000000a003', 'Rushing leader', 'pick', null, 15, 0, null),
  ('00000000-0000-0000-0000-00000000b401', '00000000-0000-0000-0000-00000000a004', 'Your top three', 'rank', 3, 18, 0, array['00000000-0000-0000-0000-00000000c402'::uuid, '00000000-0000-0000-0000-00000000c401'::uuid, '00000000-0000-0000-0000-00000000c403'::uuid]),
  ('00000000-0000-0000-0000-00000000b501', '00000000-0000-0000-0000-00000000a005', 'AFC East winner', 'pick', null, 12, 0, array['00000000-0000-0000-0000-00000000c501'::uuid]),
  ('00000000-0000-0000-0000-00000000b502', '00000000-0000-0000-0000-00000000a005', 'Two AFC wild cards', 'pick_set', 2, 12, 1, array['00000000-0000-0000-0000-00000000c504'::uuid, '00000000-0000-0000-0000-00000000c505'::uuid]),
  ('00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000a006', 'Patriots @ Seahawks', 'pick', null, 10, 0, null);

insert into public.prompt_slot_options (id, slot_id, label, sublabel, team_code, sort_order)
values
  ('00000000-0000-0000-0000-00000000c101', '00000000-0000-0000-0000-00000000b101', 'Chiefs', 'Away', 'KC', 0), ('00000000-0000-0000-0000-00000000c102', '00000000-0000-0000-0000-00000000b101', 'Bills', 'Home', 'BUF', 1),
  ('00000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000b201', 'Ravens', 'Away', 'BAL', 0), ('00000000-0000-0000-0000-00000000c202', '00000000-0000-0000-0000-00000000b201', 'Bengals', 'Home', 'CIN', 1),
  ('00000000-0000-0000-0000-00000000c203', '00000000-0000-0000-0000-00000000b202', 'Cowboys', 'Away', 'DAL', 0), ('00000000-0000-0000-0000-00000000c204', '00000000-0000-0000-0000-00000000b202', 'Eagles', 'Home', 'PHI', 1),
  ('00000000-0000-0000-0000-00000000c205', '00000000-0000-0000-0000-00000000b203', 'Broncos', 'Away', 'DEN', 0), ('00000000-0000-0000-0000-00000000c206', '00000000-0000-0000-0000-00000000b203', 'Chargers', 'Home', 'LAC', 1),
  ('00000000-0000-0000-0000-00000000c301', '00000000-0000-0000-0000-00000000b301', 'Bijan Robinson', 'ATL · RB', null, 0), ('00000000-0000-0000-0000-00000000c302', '00000000-0000-0000-0000-00000000b301', 'Jahmyr Gibbs', 'DET · RB', null, 1), ('00000000-0000-0000-0000-00000000c303', '00000000-0000-0000-0000-00000000b301', 'Saquon Barkley', 'PHI · RB', null, 2), ('00000000-0000-0000-0000-00000000c304', '00000000-0000-0000-0000-00000000b301', 'Derrick Henry', 'BAL · RB', null, 3),
  ('00000000-0000-0000-0000-00000000c401', '00000000-0000-0000-0000-00000000b401', 'Bills', null, 'BUF', 0), ('00000000-0000-0000-0000-00000000c402', '00000000-0000-0000-0000-00000000b401', 'Chiefs', null, 'KC', 1), ('00000000-0000-0000-0000-00000000c403', '00000000-0000-0000-0000-00000000b401', 'Eagles', null, 'PHI', 2), ('00000000-0000-0000-0000-00000000c404', '00000000-0000-0000-0000-00000000b401', 'Ravens', null, 'BAL', 3),
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-00000000b501', 'Bills', null, 'BUF', 0), ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-00000000b501', 'Dolphins', null, 'MIA', 1), ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-00000000b501', 'Jets', null, 'NYJ', 2),
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-00000000b502', 'Ravens', null, 'BAL', 0), ('00000000-0000-0000-0000-00000000c505', '00000000-0000-0000-0000-00000000b502', 'Chargers', null, 'LAC', 1), ('00000000-0000-0000-0000-00000000c506', '00000000-0000-0000-0000-00000000b502', 'Bengals', null, 'CIN', 2),
  ('00000000-0000-0000-0000-00000000c601', '00000000-0000-0000-0000-00000000b601', 'Patriots', 'Away', 'NE', 0), ('00000000-0000-0000-0000-00000000c602', '00000000-0000-0000-0000-00000000b601', 'Seahawks', 'Home', 'SEA', 1);

insert into public.prompt_slot_exclusions (slot_id, excluded_slot_id)
values ('00000000-0000-0000-0000-00000000b502', '00000000-0000-0000-0000-00000000b501');

-- Demo Reader's calls show the personal-result treatments; Tasha supplies
-- enough additional responses for every aggregate bar to have a value.
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
values
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b201', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c201'::uuid], null),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b202', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c204'::uuid], null),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b203', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c206'::uuid], null),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000b301', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c302'::uuid], null),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-00000000b401', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c401'::uuid, '00000000-0000-0000-0000-00000000c402'::uuid, '00000000-0000-0000-0000-00000000c403'::uuid], 6),
  ('00000000-0000-0000-0000-00000000a005', '00000000-0000-0000-0000-00000000b501', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c501'::uuid], 12),
  ('00000000-0000-0000-0000-00000000a005', '00000000-0000-0000-0000-00000000b502', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c504'::uuid, '00000000-0000-0000-0000-00000000c506'::uuid], 6),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b201', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c202'::uuid], null),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b202', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c204'::uuid], null),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b203', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c205'::uuid], null),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b201', '00000000-0000-0000-0000-00000000d002', array['00000000-0000-0000-0000-00000000c201'::uuid], null),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b202', '00000000-0000-0000-0000-00000000d002', array['00000000-0000-0000-0000-00000000c203'::uuid], null),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000b203', '00000000-0000-0000-0000-00000000d002', array['00000000-0000-0000-0000-00000000c206'::uuid], null),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000b301', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c301'::uuid], null);

insert into private.prompt_slot_answers (slot_id, correct_option_ids)
values
  ('00000000-0000-0000-0000-00000000b401', array['00000000-0000-0000-0000-00000000c402'::uuid, '00000000-0000-0000-0000-00000000c401'::uuid, '00000000-0000-0000-0000-00000000c403'::uuid]),
  ('00000000-0000-0000-0000-00000000b501', array['00000000-0000-0000-0000-00000000c501'::uuid]),
  ('00000000-0000-0000-0000-00000000b502', array['00000000-0000-0000-0000-00000000c504'::uuid, '00000000-0000-0000-0000-00000000c505'::uuid]);

insert into public.prompt_comments (post_id, author_id, body, posted_with_pick, created_at)
values
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000d003', 'Ravens on the road feels like the sharp call.', true, now() - interval '1 day'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000d002', 'I am fading Dallas, but the home teams carry the rest of this ticket.', true, now() - interval '20 hours'),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-00000000d003', 'I had the Bills one spot too high.', false, now() - interval '3 days');

commit;
