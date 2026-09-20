-- Local development only. Never applied to a deployed environment: `db reset`
-- runs this after the migrations, and nothing else does.
--
-- The hosted project grants every table in `public` to anon and authenticated
-- by default, leaving RLS as the only gate. A local CLI stack no longer sets
-- those default privileges, so without this the app and the tests would hit
-- "permission denied" locally for tables that work fine in production — a
-- difference in environment defaults masquerading as a bug in the code.
--
-- The profile editor is the one intentional exception: it updates the
-- caller's own profile through the authenticated server client. RLS still
-- limits that write to auth.uid() = id; this grant only gives the local stack
-- the same table privilege the hosted project supplies.
grant select on all tables in schema public to anon, authenticated;
grant update on table public.profiles to authenticated;

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
  confirmation_token, email_change, email_change_token_new, recovery_token,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data
)
values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo@ballparty.local', crypt('ball-party-demo', gen_salt('bf')), now(), '', '', '', '', now() - interval '7 days', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Demo Reader"}'),
  ('00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'curator@ballparty.local', crypt('ball-party-demo', gen_salt('bf')), now(), '', '', '', '', now() - interval '7 days', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Ball Curator"}'),
  ('00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tasha@ballparty.local', crypt('ball-party-demo', gen_salt('bf')), now(), '', '', '', '', now() - interval '7 days', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Tasha"}');

insert into public.prompt_posts (
  id, template_kind, template_name, author_id, caption, prompt_text,
  resolution_criteria, lock_at, status, void_reason, created_at, resolved_at
)
values
  -- Open + unanswered: the CTA and dedicated single-game pick screen.
  ('00000000-0000-0000-0000-00000000a001', 'picks', 'Single game picks', '00000000-0000-0000-0000-00000000d002', 'Sunday night, no hedging.', 'Who wins Chiefs @ Bills?', 'The winner is the team with more points at final whistle.', now() + interval '3 days', 'open', null, now() - interval '20 minutes', null),
  -- Open + unanswered: the full 2026 Week 2 ticket for the demo account.
  ('00000000-0000-0000-0000-00000000a002', 'weekly_picks', '2026 Week 2 · Full slate', '00000000-0000-0000-0000-00000000d002', 'Sixteen games. One ticket. No hedging.', 'Pick every 2026 Week 2 winner', 'Each game resolves from its final score.', now() + interval '6 days', 'open', null, now() - interval '45 minutes', null),
  -- Open + answered: generic card result mode before the answer is known.
  ('00000000-0000-0000-0000-00000000a003', 'stat_leader', 'Stat leader', '00000000-0000-0000-0000-00000000d002', 'Settle the Sunday argument early.', 'Who leads the league in rushing yards?', 'Official regular-season rushing-yard total after Week 18.', now() + interval '10 days', 'open', null, now() - interval '3 hours', null),
  -- Resolved rank: partial-credit order, correct/wrong rows, and scoremark.
  ('00000000-0000-0000-0000-00000000a004', 'ranking', 'Top-three ranking', '00000000-0000-0000-0000-00000000d002', 'Rank the three offenses you trust most.', 'Rank these offenses', 'The editorial panel publishes its Week 1 power ranking.', now() - interval '5 days', 'resolved', null, now() - interval '8 days', now() - interval '4 days'),
  -- Resolved custom multi: pick, pick-set and cross-slot result faces.
  ('00000000-0000-0000-0000-00000000a005', 'custom_multi', 'Preseason calls', '00000000-0000-0000-0000-00000000d002', 'A division winner and two wild cards — no duplicates.', 'Build your AFC playoff picture', 'The post resolves against the final AFC playoff field.', now() - interval '12 days', 'resolved', null, now() - interval '20 days', now() - interval '11 days'),
  -- Resolved: a finished Monday-night game with picks, takes, and replies.
  ('00000000-0000-0000-0000-00000000a006', 'game_pick', 'Monday Night Football · Week 1', '00000000-0000-0000-0000-00000000d002', 'Arrowhead under the lights. Who had it?', 'Broncos @ Chiefs', 'Kansas City won 24–10 on Monday Night Football.', now() - interval '2 days', 'resolved', null, now() - interval '5 days', now() - interval '1 day'),
  -- Resolved: an eight-game weekly ticket with a partially correct demo call.
  ('00000000-0000-0000-0000-00000000a007', 'weekly_picks', '2026 Week 1 · Sunday sampler', '00000000-0000-0000-0000-00000000d002', 'Eight Week 1 calls, with just enough chaos.', 'How did you see Week 1 playing out?', 'Each game resolves from its final score.', now() - interval '3 days', 'resolved', null, now() - interval '6 days', now() - interval '2 days');

insert into public.prompt_slots (id, post_id, label, shape, pick_count, points, sort_order, correct_option_ids)
values
  ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-00000000a001', 'Chiefs @ Bills', 'pick', null, 10, 0, null),
  ('00000000-0000-0000-0000-00000000b201', '00000000-0000-0000-0000-00000000a002', 'Lions @ Bills', 'pick', null, 10, 0, null),
  ('00000000-0000-0000-0000-00000000b202', '00000000-0000-0000-0000-00000000a002', 'Panthers @ Falcons', 'pick', null, 10, 1, null),
  ('00000000-0000-0000-0000-00000000b203', '00000000-0000-0000-0000-00000000a002', 'Saints @ Ravens', 'pick', null, 10, 2, null),
  ('00000000-0000-0000-0000-00000000b204', '00000000-0000-0000-0000-00000000a002', 'Vikings @ Bears', 'pick', null, 10, 3, null),
  ('00000000-0000-0000-0000-00000000b205', '00000000-0000-0000-0000-00000000a002', 'Bengals @ Texans', 'pick', null, 10, 4, null),
  ('00000000-0000-0000-0000-00000000b206', '00000000-0000-0000-0000-00000000a002', 'Steelers @ Patriots', 'pick', null, 10, 5, null),
  ('00000000-0000-0000-0000-00000000b207', '00000000-0000-0000-0000-00000000a002', 'Packers @ Jets', 'pick', null, 10, 6, null),
  ('00000000-0000-0000-0000-00000000b208', '00000000-0000-0000-0000-00000000a002', 'Browns @ Buccaneers', 'pick', null, 10, 7, null),
  ('00000000-0000-0000-0000-00000000b209', '00000000-0000-0000-0000-00000000a002', 'Eagles @ Titans', 'pick', null, 10, 8, null),
  ('00000000-0000-0000-0000-00000000b210', '00000000-0000-0000-0000-00000000a002', 'Jaguars @ Broncos', 'pick', null, 10, 9, null),
  ('00000000-0000-0000-0000-00000000b211', '00000000-0000-0000-0000-00000000a002', 'Raiders @ Chargers', 'pick', null, 10, 10, null),
  ('00000000-0000-0000-0000-00000000b212', '00000000-0000-0000-0000-00000000a002', 'Seahawks @ Cardinals', 'pick', null, 10, 11, null),
  ('00000000-0000-0000-0000-00000000b213', '00000000-0000-0000-0000-00000000a002', 'Commanders @ Cowboys', 'pick', null, 10, 12, null),
  ('00000000-0000-0000-0000-00000000b214', '00000000-0000-0000-0000-00000000a002', 'Dolphins @ 49ers', 'pick', null, 10, 13, null),
  ('00000000-0000-0000-0000-00000000b215', '00000000-0000-0000-0000-00000000a002', 'Colts @ Chiefs', 'pick', null, 10, 14, null),
  ('00000000-0000-0000-0000-00000000b216', '00000000-0000-0000-0000-00000000a002', 'Giants @ Rams', 'pick', null, 10, 15, null),
  ('00000000-0000-0000-0000-00000000b301', '00000000-0000-0000-0000-00000000a003', 'Rushing leader', 'pick', null, 15, 0, null),
  ('00000000-0000-0000-0000-00000000b401', '00000000-0000-0000-0000-00000000a004', 'Your top three', 'rank', 3, 18, 0, array['00000000-0000-0000-0000-00000000c402'::uuid, '00000000-0000-0000-0000-00000000c401'::uuid, '00000000-0000-0000-0000-00000000c403'::uuid]),
  ('00000000-0000-0000-0000-00000000b501', '00000000-0000-0000-0000-00000000a005', 'AFC East winner', 'pick', null, 12, 0, array['00000000-0000-0000-0000-00000000c501'::uuid]),
  ('00000000-0000-0000-0000-00000000b502', '00000000-0000-0000-0000-00000000a005', 'Two AFC wild cards', 'pick_set', 2, 12, 1, array['00000000-0000-0000-0000-00000000c504'::uuid, '00000000-0000-0000-0000-00000000c505'::uuid]),
  ('00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000a006', 'Broncos @ Chiefs', 'pick', null, 10, 0, array['00000000-0000-0000-0000-00000000c602'::uuid]),
  ('00000000-0000-0000-0000-00000000b701', '00000000-0000-0000-0000-00000000a007', 'Patriots @ Seahawks', 'pick', null, 10, 0, array['00000000-0000-0000-0000-00000000c702'::uuid]),
  ('00000000-0000-0000-0000-00000000b702', '00000000-0000-0000-0000-00000000a007', '49ers @ Rams', 'pick', null, 10, 1, array['00000000-0000-0000-0000-00000000c703'::uuid]),
  ('00000000-0000-0000-0000-00000000b703', '00000000-0000-0000-0000-00000000a007', 'Bears @ Panthers', 'pick', null, 10, 2, array['00000000-0000-0000-0000-00000000c705'::uuid]),
  ('00000000-0000-0000-0000-00000000b704', '00000000-0000-0000-0000-00000000a007', 'Buccaneers @ Bengals', 'pick', null, 10, 3, array['00000000-0000-0000-0000-00000000c708'::uuid]),
  ('00000000-0000-0000-0000-00000000b705', '00000000-0000-0000-0000-00000000a007', 'Ravens @ Colts', 'pick', null, 10, 4, array['00000000-0000-0000-0000-00000000c709'::uuid]),
  ('00000000-0000-0000-0000-00000000b706', '00000000-0000-0000-0000-00000000a007', 'Saints @ Lions', 'pick', null, 10, 5, array['00000000-0000-0000-0000-00000000c712'::uuid]),
  ('00000000-0000-0000-0000-00000000b707', '00000000-0000-0000-0000-00000000a007', 'Falcons @ Steelers', 'pick', null, 10, 6, array['00000000-0000-0000-0000-00000000c714'::uuid]),
  ('00000000-0000-0000-0000-00000000b708', '00000000-0000-0000-0000-00000000a007', 'Broncos @ Chiefs', 'pick', null, 10, 7, array['00000000-0000-0000-0000-00000000c716'::uuid]);

-- Schedule details for the matchup covers (0119). The `seed_` ids keep these
-- apart from the real nflverse rows the poll loads, so the gallery reads the
-- same with or without the network. Kickoffs are relative so the open posts'
-- games stay in the future however old this database gets.
insert into public.nfl_games (id, season, week, kickoff, away_team, home_team, stadium, primetime)
values
  ('seed_2026_02_KC_BUF',  2026, 2, now() + interval '3 days' + interval '2 hours',  'KC',  'BUF', 'Highmark Stadium',            true),
  ('seed_2026_02_DET_BUF', 2026, 2, now() + interval '6 days',                       'DET', 'BUF', 'Highmark Stadium',            false),
  ('seed_2026_02_CAR_ATL', 2026, 2, now() + interval '6 days',                       'CAR', 'ATL', 'Mercedes-Benz Stadium',       false),
  ('seed_2026_02_NO_BAL',  2026, 2, now() + interval '7 days' + interval '3 hours',  'NO',  'BAL', 'M&T Bank Stadium',            true),
  ('seed_2026_02_MIN_CHI', 2026, 2, now() + interval '6 days' + interval '3 hours',  'MIN', 'CHI', 'Soldier Field',               false),
  ('seed_2026_01_DEN_KC',  2026, 1, now() - interval '5 days',                       'DEN', 'KC',  'GEHA Field at Arrowhead Stadium', true),
  ('seed_2026_01_NE_SEA',  2026, 1, now() - interval '6 days',                       'NE',  'SEA', 'Lumen Field',                 true),
  ('seed_2026_01_SF_LA',   2026, 1, now() - interval '6 days' + interval '1 day',    'SF',  'LA',  'SoFi Stadium',                false)
on conflict (id) do nothing;

update public.prompt_slots as s
   set source_game_id = g.game_id
  from (values
    ('00000000-0000-0000-0000-00000000b101'::uuid, 'seed_2026_02_KC_BUF'),
    ('00000000-0000-0000-0000-00000000b201'::uuid, 'seed_2026_02_DET_BUF'),
    ('00000000-0000-0000-0000-00000000b202'::uuid, 'seed_2026_02_CAR_ATL'),
    ('00000000-0000-0000-0000-00000000b203'::uuid, 'seed_2026_02_NO_BAL'),
    ('00000000-0000-0000-0000-00000000b204'::uuid, 'seed_2026_02_MIN_CHI'),
    ('00000000-0000-0000-0000-00000000b601'::uuid, 'seed_2026_01_DEN_KC'),
    ('00000000-0000-0000-0000-00000000b701'::uuid, 'seed_2026_01_NE_SEA'),
    ('00000000-0000-0000-0000-00000000b702'::uuid, 'seed_2026_01_SF_LA')
  ) as g(slot_id, game_id)
 where s.id = g.slot_id;

insert into public.prompt_slot_options (id, slot_id, label, sublabel, team_code, sort_order)
values
  ('00000000-0000-0000-0000-00000000c101', '00000000-0000-0000-0000-00000000b101', 'Chiefs', 'Away', 'KC', 0), ('00000000-0000-0000-0000-00000000c102', '00000000-0000-0000-0000-00000000b101', 'Bills', 'Home', 'BUF', 1),
  ('00000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000b201', 'Lions', 'Away', 'DET', 0), ('00000000-0000-0000-0000-00000000c202', '00000000-0000-0000-0000-00000000b201', 'Bills', 'Home', 'BUF', 1),
  ('00000000-0000-0000-0000-00000000c203', '00000000-0000-0000-0000-00000000b202', 'Panthers', 'Away', 'CAR', 0), ('00000000-0000-0000-0000-00000000c204', '00000000-0000-0000-0000-00000000b202', 'Falcons', 'Home', 'ATL', 1),
  ('00000000-0000-0000-0000-00000000c205', '00000000-0000-0000-0000-00000000b203', 'Saints', 'Away', 'NO', 0), ('00000000-0000-0000-0000-00000000c206', '00000000-0000-0000-0000-00000000b203', 'Ravens', 'Home', 'BAL', 1),
  ('00000000-0000-0000-0000-00000000c207', '00000000-0000-0000-0000-00000000b204', 'Vikings', 'Away', 'MIN', 0), ('00000000-0000-0000-0000-00000000c208', '00000000-0000-0000-0000-00000000b204', 'Bears', 'Home', 'CHI', 1),
  ('00000000-0000-0000-0000-00000000c209', '00000000-0000-0000-0000-00000000b205', 'Bengals', 'Away', 'CIN', 0), ('00000000-0000-0000-0000-00000000c210', '00000000-0000-0000-0000-00000000b205', 'Texans', 'Home', 'HOU', 1),
  ('00000000-0000-0000-0000-00000000c211', '00000000-0000-0000-0000-00000000b206', 'Steelers', 'Away', 'PIT', 0), ('00000000-0000-0000-0000-00000000c212', '00000000-0000-0000-0000-00000000b206', 'Patriots', 'Home', 'NE', 1),
  ('00000000-0000-0000-0000-00000000c213', '00000000-0000-0000-0000-00000000b207', 'Packers', 'Away', 'GB', 0), ('00000000-0000-0000-0000-00000000c214', '00000000-0000-0000-0000-00000000b207', 'Jets', 'Home', 'NYJ', 1),
  ('00000000-0000-0000-0000-00000000c215', '00000000-0000-0000-0000-00000000b208', 'Browns', 'Away', 'CLE', 0), ('00000000-0000-0000-0000-00000000c216', '00000000-0000-0000-0000-00000000b208', 'Buccaneers', 'Home', 'TB', 1),
  ('00000000-0000-0000-0000-00000000c217', '00000000-0000-0000-0000-00000000b209', 'Eagles', 'Away', 'PHI', 0), ('00000000-0000-0000-0000-00000000c218', '00000000-0000-0000-0000-00000000b209', 'Titans', 'Home', 'TEN', 1),
  ('00000000-0000-0000-0000-00000000c219', '00000000-0000-0000-0000-00000000b210', 'Jaguars', 'Away', 'JAX', 0), ('00000000-0000-0000-0000-00000000c220', '00000000-0000-0000-0000-00000000b210', 'Broncos', 'Home', 'DEN', 1),
  ('00000000-0000-0000-0000-00000000c221', '00000000-0000-0000-0000-00000000b211', 'Raiders', 'Away', 'LV', 0), ('00000000-0000-0000-0000-00000000c222', '00000000-0000-0000-0000-00000000b211', 'Chargers', 'Home', 'LAC', 1),
  ('00000000-0000-0000-0000-00000000c223', '00000000-0000-0000-0000-00000000b212', 'Seahawks', 'Away', 'SEA', 0), ('00000000-0000-0000-0000-00000000c224', '00000000-0000-0000-0000-00000000b212', 'Cardinals', 'Home', 'ARI', 1),
  ('00000000-0000-0000-0000-00000000c225', '00000000-0000-0000-0000-00000000b213', 'Commanders', 'Away', 'WAS', 0), ('00000000-0000-0000-0000-00000000c226', '00000000-0000-0000-0000-00000000b213', 'Cowboys', 'Home', 'DAL', 1),
  ('00000000-0000-0000-0000-00000000c227', '00000000-0000-0000-0000-00000000b214', 'Dolphins', 'Away', 'MIA', 0), ('00000000-0000-0000-0000-00000000c228', '00000000-0000-0000-0000-00000000b214', '49ers', 'Home', 'SF', 1),
  ('00000000-0000-0000-0000-00000000c229', '00000000-0000-0000-0000-00000000b215', 'Colts', 'Away', 'IND', 0), ('00000000-0000-0000-0000-00000000c230', '00000000-0000-0000-0000-00000000b215', 'Chiefs', 'Home', 'KC', 1),
  ('00000000-0000-0000-0000-00000000c231', '00000000-0000-0000-0000-00000000b216', 'Giants', 'Away', 'NYG', 0), ('00000000-0000-0000-0000-00000000c232', '00000000-0000-0000-0000-00000000b216', 'Rams', 'Home', 'LAR', 1),
  ('00000000-0000-0000-0000-00000000c301', '00000000-0000-0000-0000-00000000b301', 'Bijan Robinson', 'ATL · RB', null, 0), ('00000000-0000-0000-0000-00000000c302', '00000000-0000-0000-0000-00000000b301', 'Jahmyr Gibbs', 'DET · RB', null, 1), ('00000000-0000-0000-0000-00000000c303', '00000000-0000-0000-0000-00000000b301', 'Saquon Barkley', 'PHI · RB', null, 2), ('00000000-0000-0000-0000-00000000c304', '00000000-0000-0000-0000-00000000b301', 'Derrick Henry', 'BAL · RB', null, 3),
  ('00000000-0000-0000-0000-00000000c401', '00000000-0000-0000-0000-00000000b401', 'Bills', null, 'BUF', 0), ('00000000-0000-0000-0000-00000000c402', '00000000-0000-0000-0000-00000000b401', 'Chiefs', null, 'KC', 1), ('00000000-0000-0000-0000-00000000c403', '00000000-0000-0000-0000-00000000b401', 'Eagles', null, 'PHI', 2), ('00000000-0000-0000-0000-00000000c404', '00000000-0000-0000-0000-00000000b401', 'Ravens', null, 'BAL', 3),
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-00000000b501', 'Bills', null, 'BUF', 0), ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-00000000b501', 'Dolphins', null, 'MIA', 1), ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-00000000b501', 'Jets', null, 'NYJ', 2),
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-00000000b502', 'Ravens', null, 'BAL', 0), ('00000000-0000-0000-0000-00000000c505', '00000000-0000-0000-0000-00000000b502', 'Chargers', null, 'LAC', 1), ('00000000-0000-0000-0000-00000000c506', '00000000-0000-0000-0000-00000000b502', 'Bengals', null, 'CIN', 2),
  ('00000000-0000-0000-0000-00000000c601', '00000000-0000-0000-0000-00000000b601', 'Broncos', 'Away', 'DEN', 0), ('00000000-0000-0000-0000-00000000c602', '00000000-0000-0000-0000-00000000b601', 'Chiefs', 'Home', 'KC', 1),
  ('00000000-0000-0000-0000-00000000c701', '00000000-0000-0000-0000-00000000b701', 'Patriots', 'Away', 'NE', 0), ('00000000-0000-0000-0000-00000000c702', '00000000-0000-0000-0000-00000000b701', 'Seahawks', 'Home', 'SEA', 1),
  ('00000000-0000-0000-0000-00000000c703', '00000000-0000-0000-0000-00000000b702', '49ers', 'Away', 'SF', 0), ('00000000-0000-0000-0000-00000000c704', '00000000-0000-0000-0000-00000000b702', 'Rams', 'Home', 'LAR', 1),
  ('00000000-0000-0000-0000-00000000c705', '00000000-0000-0000-0000-00000000b703', 'Bears', 'Away', 'CHI', 0), ('00000000-0000-0000-0000-00000000c706', '00000000-0000-0000-0000-00000000b703', 'Panthers', 'Home', 'CAR', 1),
  ('00000000-0000-0000-0000-00000000c707', '00000000-0000-0000-0000-00000000b704', 'Buccaneers', 'Away', 'TB', 0), ('00000000-0000-0000-0000-00000000c708', '00000000-0000-0000-0000-00000000b704', 'Bengals', 'Home', 'CIN', 1),
  ('00000000-0000-0000-0000-00000000c709', '00000000-0000-0000-0000-00000000b705', 'Ravens', 'Away', 'BAL', 0), ('00000000-0000-0000-0000-00000000c710', '00000000-0000-0000-0000-00000000b705', 'Colts', 'Home', 'IND', 1),
  ('00000000-0000-0000-0000-00000000c711', '00000000-0000-0000-0000-00000000b706', 'Saints', 'Away', 'NO', 0), ('00000000-0000-0000-0000-00000000c712', '00000000-0000-0000-0000-00000000b706', 'Lions', 'Home', 'DET', 1),
  ('00000000-0000-0000-0000-00000000c713', '00000000-0000-0000-0000-00000000b707', 'Falcons', 'Away', 'ATL', 0), ('00000000-0000-0000-0000-00000000c714', '00000000-0000-0000-0000-00000000b707', 'Steelers', 'Home', 'PIT', 1),
  ('00000000-0000-0000-0000-00000000c715', '00000000-0000-0000-0000-00000000b708', 'Broncos', 'Away', 'DEN', 0), ('00000000-0000-0000-0000-00000000c716', '00000000-0000-0000-0000-00000000b708', 'Chiefs', 'Home', 'KC', 1);

insert into public.prompt_slot_exclusions (slot_id, excluded_slot_id)
values ('00000000-0000-0000-0000-00000000b502', '00000000-0000-0000-0000-00000000b501');

-- Demo Reader's calls show the personal-result treatments; the Week 2 slate
-- intentionally has no responses, so demo@ballparty.local can fill it in.
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
values
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000b301', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c302'::uuid], null),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-00000000b401', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c401'::uuid, '00000000-0000-0000-0000-00000000c402'::uuid, '00000000-0000-0000-0000-00000000c403'::uuid], 6),
  ('00000000-0000-0000-0000-00000000a005', '00000000-0000-0000-0000-00000000b501', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c501'::uuid], 12),
  ('00000000-0000-0000-0000-00000000a005', '00000000-0000-0000-0000-00000000b502', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c504'::uuid, '00000000-0000-0000-0000-00000000c506'::uuid], 6),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000b301', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c301'::uuid], null),
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c602'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000d002', array['00000000-0000-0000-0000-00000000c602'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c601'::uuid], 0),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b701', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c702'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b702', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c704'::uuid], 0),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b703', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c705'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b704', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c707'::uuid], 0),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b705', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c709'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b706', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c712'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b707', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c714'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b708', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c716'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b701', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c701'::uuid], 0),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b702', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c703'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b703', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c706'::uuid], 0),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b704', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c708'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b705', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c709'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b706', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c711'::uuid], 0),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b707', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c713'::uuid], 0),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000b708', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c716'::uuid], 10);

insert into private.prompt_slot_answers (slot_id, correct_option_ids)
values
  ('00000000-0000-0000-0000-00000000b401', array['00000000-0000-0000-0000-00000000c402'::uuid, '00000000-0000-0000-0000-00000000c401'::uuid, '00000000-0000-0000-0000-00000000c403'::uuid]),
  ('00000000-0000-0000-0000-00000000b501', array['00000000-0000-0000-0000-00000000c501'::uuid]),
  ('00000000-0000-0000-0000-00000000b502', array['00000000-0000-0000-0000-00000000c504'::uuid, '00000000-0000-0000-0000-00000000c505'::uuid]),
  ('00000000-0000-0000-0000-00000000b601', array['00000000-0000-0000-0000-00000000c602'::uuid]),
  ('00000000-0000-0000-0000-00000000b701', array['00000000-0000-0000-0000-00000000c702'::uuid]),
  ('00000000-0000-0000-0000-00000000b702', array['00000000-0000-0000-0000-00000000c703'::uuid]),
  ('00000000-0000-0000-0000-00000000b703', array['00000000-0000-0000-0000-00000000c705'::uuid]),
  ('00000000-0000-0000-0000-00000000b704', array['00000000-0000-0000-0000-00000000c708'::uuid]),
  ('00000000-0000-0000-0000-00000000b705', array['00000000-0000-0000-0000-00000000c709'::uuid]),
  ('00000000-0000-0000-0000-00000000b706', array['00000000-0000-0000-0000-00000000c712'::uuid]),
  ('00000000-0000-0000-0000-00000000b707', array['00000000-0000-0000-0000-00000000c714'::uuid]),
  ('00000000-0000-0000-0000-00000000b708', array['00000000-0000-0000-0000-00000000c716'::uuid]);

insert into public.prompt_comments (id, post_id, author_id, body, posted_with_pick, parent_comment_id, created_at)
values
  ('00000000-0000-0000-0000-00000000e201', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d001', 'Kansas City at home in Week 1 was too much to pass up. The fourth quarter sealed it.', true, null, now() - interval '22 hours'),
  ('00000000-0000-0000-0000-00000000e202', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d003', 'I thought Denver would carry last season’s momentum into Arrowhead. Wrong side, but it was a fun sweat.', true, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-00000000e203', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d002', 'Mahomes looked composed after halftime. Chiefs was my easiest call of the opener.', true, null, now() - interval '20 hours'),
  ('00000000-0000-0000-0000-00000000e204', '00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-00000000d003', 'I had the Bills one spot too high.', false, null, now() - interval '3 days'),
  ('00000000-0000-0000-0000-00000000e205', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d002', 'Denver’s defense kept it close early. The last 15 minutes changed the whole feel of it.', false, '00000000-0000-0000-0000-00000000e202', now() - interval '18 hours'),
  ('00000000-0000-0000-0000-00000000e206', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d001', 'Exactly. I was relieved to see that one turn into a comfortable finish.', false, '00000000-0000-0000-0000-00000000e203', now() - interval '16 hours'),
  ('00000000-0000-0000-0000-00000000e207', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d003', 'Fair. I am taking Denver again when they get the rematch at home.', false, '00000000-0000-0000-0000-00000000e202', now() - interval '12 hours');

commit;
