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
-- A local-only gallery for exercising the prompt-card templates and lifecycle
-- treatments at /social. Sign in as `demo@ballparty.local` with password
-- `ball-party-demo` after `npm --prefix webapp run db:reset`.
--
--   open, unanswered   single game pick · Week 2 full slate (16 games) ·
--                      Power Rankings
--   closed, answered   single game pick (resolved) · Week 1 full slate (16
--                      games, resolved) · two Power Rankings (locked — an
--                      opinion post is never resolvable, so locked is as
--                      closed as it gets)
--
-- Open posts lock a month out so the gallery stays usable without a reseed.
-- The other respondents make the aggregate bars non-trivial.
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
  resolution_criteria, lock_at, status, void_reason, created_at, resolved_at,
  is_opinion, cover_team_codes
)
values
  -- Open + unanswered: the CTA and dedicated single-game pick screen.
  ('00000000-0000-0000-0000-00000000a001', 'picks', 'Single game picks', '00000000-0000-0000-0000-00000000d002', 'Sunday night, no hedging.', 'Who wins Chiefs @ Bills?', 'The winner is the team with more points at final whistle.', now() + interval '30 days', 'open', null, now() - interval '20 minutes', null, false, null),
  -- Open + unanswered: the full 2026 Week 2 ticket for the demo account.
  ('00000000-0000-0000-0000-00000000a002', 'weekly_picks', '2026 Week 2 · Full slate', '00000000-0000-0000-0000-00000000d002', 'Sixteen games. One ticket. No hedging.', 'Pick every 2026 Week 2 winner', 'Each game resolves from its final score.', now() + interval '30 days', 'open', null, now() - interval '45 minutes', null, false, null),
  -- Resolved + answered: a finished Monday-night game with picks, takes, and replies.
  ('00000000-0000-0000-0000-00000000a006', 'picks', 'Single game picks', '00000000-0000-0000-0000-00000000d002', 'Arrowhead under the lights. Who had it?', 'Who won Broncos @ Chiefs?', 'The winner is the team with more points at final whistle.', now() - interval '5 days', 'resolved', null, now() - interval '8 days', now() - interval '4 days', false, null),
  -- Resolved + answered: a sixteen-game weekly ticket with a partially correct demo call.
  ('00000000-0000-0000-0000-00000000a007', 'weekly_picks', '2026 Week 1 · Full slate', '00000000-0000-0000-0000-00000000d002', 'Sixteen Week 1 calls, with just enough chaos.', 'How did you see Week 1 playing out?', 'Each game resolves from its final score.', now() - interval '6 days', 'resolved', null, now() - interval '9 days', now() - interval '5 days', false, null),
  -- Power Rankings are opinion-only, so "closed" means locked, never resolved.
  ('00000000-0000-0000-0000-00000000a010', 'power_rankings', 'Power Rankings · Week 1', '00000000-0000-0000-0000-00000000d002', 'Where does everyone stand after opening weekend?', 'Rank the NFL after Week 1', 'Opinion prompt — there is no correct answer.', now() - interval '14 days', 'locked', null, now() - interval '17 days', null, true, array['BAL', 'GB', 'TB', 'KC', 'PHI', 'BUF']),
  ('00000000-0000-0000-0000-00000000a011', 'power_rankings', 'Power Rankings · Week 2', '00000000-0000-0000-0000-00000000d002', 'One week of tape. Who moved?', 'Rank the NFL after Week 2', 'Opinion prompt — there is no correct answer.', now() - interval '7 days', 'locked', null, now() - interval '10 days', null, true, array['DET', 'BUF', 'KC', 'SF', 'PHI', 'BAL']),
  ('00000000-0000-0000-0000-00000000a012', 'power_rankings', 'Power Rankings · Week 3', '00000000-0000-0000-0000-00000000d002', 'Sort the league your way.', 'Rank the NFL after Week 3', 'Opinion prompt — there is no correct answer.', now() + interval '30 days', 'open', null, now() - interval '1 hour', null, true, array['KC', 'BUF', 'DET', 'PHI', 'BAL', 'SF']);

-- Schedule details for the matchup covers (0119). The `seed_` ids keep these
-- apart from the real nflverse rows the poll loads, so the gallery reads the
-- same with or without the network. Kickoffs are relative so the open posts'
-- games stay in the future however old this database gets.
insert into public.nfl_games (id, season, week, kickoff, away_team, home_team, stadium, primetime)
values
  ('seed_2026_02_KC_BUF',  2026, 2, now() + interval '30 days' + interval '2 hours', 'KC',  'BUF', 'Highmark Stadium',            true),
  ('seed_2026_02_DET_BUF', 2026, 2, now() + interval '30 days',                      'DET', 'BUF', 'Highmark Stadium',            false),
  ('seed_2026_02_CAR_ATL', 2026, 2, now() + interval '30 days',                      'CAR', 'ATL', 'Mercedes-Benz Stadium',       false),
  ('seed_2026_02_NO_BAL',  2026, 2, now() + interval '31 days' + interval '3 hours', 'NO',  'BAL', 'M&T Bank Stadium',            true),
  ('seed_2026_02_MIN_CHI', 2026, 2, now() + interval '30 days' + interval '3 hours', 'MIN', 'CHI', 'Soldier Field',               false),
  ('seed_2026_01_DEN_KC',  2026, 1, now() - interval '5 days',                       'DEN', 'KC',  'GEHA Field at Arrowhead Stadium', true),
  ('seed_2026_01_NE_SEA',  2026, 1, now() - interval '6 days',                       'NE',  'SEA', 'Lumen Field',                 true),
  ('seed_2026_01_SF_LA',   2026, 1, now() - interval '6 days' + interval '1 day',    'SF',  'LA',  'SoFi Stadium',                false)
on conflict (id) do nothing;

-- Week 1 board. winner / demo / tasha are 'A' (away) or 'H' (home). One table
-- drives the slots, options, answers and responses so the four can't drift.
-- Option ids follow the slot index: away = c7(2i+1), home = c7(2i+2).
create temp table wk1_games (
  idx int, away_name text, away_code text, home_name text, home_code text,
  winner char(1), demo char(1), tasha char(1), source_game_id text,
  slot_id uuid, away_option uuid, home_option uuid
) on commit drop;

insert into wk1_games (idx, away_name, away_code, home_name, home_code, winner, demo, tasha, source_game_id)
values
  (0,  'Patriots',   'NE',  'Seahawks',  'SEA', 'H', 'H', 'A', 'seed_2026_01_NE_SEA'),
  (1,  '49ers',      'SF',  'Rams',      'LAR', 'A', 'H', 'A', 'seed_2026_01_SF_LA'),
  (2,  'Bears',      'CHI', 'Panthers',  'CAR', 'A', 'A', 'H', null),
  (3,  'Buccaneers', 'TB',  'Bengals',   'CIN', 'H', 'A', 'H', null),
  (4,  'Ravens',     'BAL', 'Colts',     'IND', 'A', 'A', 'A', null),
  (5,  'Saints',     'NO',  'Lions',     'DET', 'H', 'H', 'A', null),
  (6,  'Falcons',    'ATL', 'Steelers',  'PIT', 'H', 'H', 'A', null),
  (7,  'Broncos',    'DEN', 'Chiefs',    'KC',  'H', 'H', 'H', 'seed_2026_01_DEN_KC'),
  (8,  'Cowboys',    'DAL', 'Eagles',    'PHI', 'H', 'H', 'H', null),
  (9,  'Commanders', 'WAS', 'Giants',    'NYG', 'A', 'H', 'A', null),
  (10, 'Vikings',    'MIN', 'Packers',   'GB',  'H', 'H', 'A', null),
  (11, 'Dolphins',   'MIA', 'Bills',     'BUF', 'H', 'H', 'H', null),
  (12, 'Texans',     'HOU', 'Jaguars',   'JAX', 'A', 'A', 'H', null),
  (13, 'Titans',     'TEN', 'Browns',    'CLE', 'H', 'A', 'A', null),
  (14, 'Raiders',    'LV',  'Chargers',  'LAC', 'H', 'H', 'A', null),
  (15, 'Jets',       'NYJ', 'Cardinals', 'ARI', 'H', 'A', 'H', null);

update wk1_games
   set slot_id     = ('00000000-0000-0000-0000-00000000b7' || lpad((idx + 1)::text, 2, '0'))::uuid,
       away_option = ('00000000-0000-0000-0000-00000000c7' || lpad((2 * idx + 1)::text, 2, '0'))::uuid,
       home_option = ('00000000-0000-0000-0000-00000000c7' || lpad((2 * idx + 2)::text, 2, '0'))::uuid;

-- Power Rankings pool: every post ranks the same 32 teams. Option ids encode
-- the post number and the team's alphabetical position.
create temp table power_teams (code text, name text, sort int) on commit drop;
insert into power_teams (code, name, sort)
select code, name, row_number() over (order by code) - 1
from (values
  ('ARI', 'Cardinals'), ('ATL', 'Falcons'), ('BAL', 'Ravens'), ('BUF', 'Bills'),
  ('CAR', 'Panthers'), ('CHI', 'Bears'), ('CIN', 'Bengals'), ('CLE', 'Browns'),
  ('DAL', 'Cowboys'), ('DEN', 'Broncos'), ('DET', 'Lions'), ('GB', 'Packers'),
  ('HOU', 'Texans'), ('IND', 'Colts'), ('JAX', 'Jaguars'), ('KC', 'Chiefs'),
  ('LAC', 'Chargers'), ('LAR', 'Rams'), ('LV', 'Raiders'), ('MIA', 'Dolphins'),
  ('MIN', 'Vikings'), ('NE', 'Patriots'), ('NO', 'Saints'), ('NYG', 'Giants'),
  ('NYJ', 'Jets'), ('PHI', 'Eagles'), ('PIT', 'Steelers'), ('SEA', 'Seahawks'),
  ('SF', '49ers'), ('TB', 'Buccaneers'), ('TEN', 'Titans'), ('WAS', 'Commanders')
) as t(code, name);

create temp table power_posts (n int, post_id uuid, slot_id uuid) on commit drop;
insert into power_posts (n, post_id, slot_id)
values
  (1, '00000000-0000-0000-0000-00000000a010', '00000000-0000-0000-0000-00000000b010'),
  (2, '00000000-0000-0000-0000-00000000a011', '00000000-0000-0000-0000-00000000b011'),
  (3, '00000000-0000-0000-0000-00000000a012', '00000000-0000-0000-0000-00000000b012');

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
  ('00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000a006', 'Broncos @ Chiefs', 'pick', null, 10, 0, array['00000000-0000-0000-0000-00000000c602'::uuid]);

insert into public.prompt_slots (id, post_id, label, shape, pick_count, points, sort_order, correct_option_ids)
select slot_id, '00000000-0000-0000-0000-00000000a007', away_name || ' @ ' || home_name, 'pick', null, 10, idx,
       array[case winner when 'A' then away_option else home_option end]
  from wk1_games;

insert into public.prompt_slots (id, post_id, label, shape, pick_count, points, sort_order, correct_option_ids)
select slot_id, post_id, 'Your power rankings', 'rank', 32, 10, 0, null
  from power_posts;

update public.prompt_slots as s
   set source_game_id = g.game_id
  from (values
    ('00000000-0000-0000-0000-00000000b101'::uuid, 'seed_2026_02_KC_BUF'),
    ('00000000-0000-0000-0000-00000000b201'::uuid, 'seed_2026_02_DET_BUF'),
    ('00000000-0000-0000-0000-00000000b202'::uuid, 'seed_2026_02_CAR_ATL'),
    ('00000000-0000-0000-0000-00000000b203'::uuid, 'seed_2026_02_NO_BAL'),
    ('00000000-0000-0000-0000-00000000b204'::uuid, 'seed_2026_02_MIN_CHI'),
    ('00000000-0000-0000-0000-00000000b601'::uuid, 'seed_2026_01_DEN_KC')
  ) as g(slot_id, game_id)
 where s.id = g.slot_id;

update public.prompt_slots as s
   set source_game_id = g.source_game_id
  from wk1_games g
 where s.id = g.slot_id and g.source_game_id is not null;

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
  ('00000000-0000-0000-0000-00000000c601', '00000000-0000-0000-0000-00000000b601', 'Broncos', 'Away', 'DEN', 0), ('00000000-0000-0000-0000-00000000c602', '00000000-0000-0000-0000-00000000b601', 'Chiefs', 'Home', 'KC', 1);

insert into public.prompt_slot_options (id, slot_id, label, sublabel, team_code, sort_order)
select away_option, slot_id, away_name, 'Away', away_code, 0 from wk1_games
union all
select home_option, slot_id, home_name, 'Home', home_code, 1 from wk1_games;

insert into public.prompt_slot_options (id, slot_id, label, sublabel, team_code, sort_order)
select ('00000000-0000-0000-000' || p.n || '-0000000000' || lpad(t.sort::text, 2, '0'))::uuid,
       p.slot_id, t.name, null, t.code, t.sort
  from power_posts p
  cross join power_teams t;

-- Demo Reader's calls show the personal-result treatments; the open posts
-- intentionally have no demo responses, so demo@ballparty.local can fill them in.
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
values
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000d001', array['00000000-0000-0000-0000-00000000c602'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000d002', array['00000000-0000-0000-0000-00000000c602'::uuid], 10),
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000b601', '00000000-0000-0000-0000-00000000d003', array['00000000-0000-0000-0000-00000000c601'::uuid], 0);

insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
select '00000000-0000-0000-0000-00000000a007', g.slot_id, p.profile_id,
       array[case p.side when 'A' then g.away_option else g.home_option end],
       case when p.side = g.winner then 10 else 0 end
  from wk1_games g
  cross join lateral (values
    ('00000000-0000-0000-0000-00000000d001'::uuid, g.demo),
    ('00000000-0000-0000-0000-00000000d003'::uuid, g.tasha)
  ) as p(profile_id, side);

-- Power Rankings ballots list team codes best-first. A respondent chooses how
-- many teams to rank (5, 10, or all 32); Week 2 reshuffles the demo ballot so
-- the movement arrows have something to show. Opinion posts earn no points.
create temp table power_ballots (n int, profile_id uuid, codes text[]) on commit drop;
insert into power_ballots (n, profile_id, codes)
values
  (1, '00000000-0000-0000-0000-00000000d001', array['KC', 'BUF', 'PHI', 'BAL', 'DET', 'SF', 'GB', 'HOU', 'CIN', 'LAR']),
  (1, '00000000-0000-0000-0000-00000000d003', array['BUF', 'KC', 'BAL', 'PHI', 'DET']),
  (1, '00000000-0000-0000-0000-00000000d002', array['KC', 'PHI', 'BUF', 'DET', 'BAL', 'SF', 'LAR', 'GB', 'HOU', 'MIN']),
  (2, '00000000-0000-0000-0000-00000000d001', array['BUF', 'KC', 'DET', 'PHI', 'BAL', 'GB', 'SF', 'HOU', 'LAR', 'MIN']),
  (2, '00000000-0000-0000-0000-00000000d003', array['KC', 'DET', 'BUF', 'PHI', 'SF']),
  (2, '00000000-0000-0000-0000-00000000d002', array['DET', 'KC', 'BUF', 'BAL', 'PHI']);

insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids, points_earned)
select p.post_id, p.slot_id, b.profile_id,
       array(
         select o.id
           from unnest(b.codes) with ordinality as t(code, ord)
           join public.prompt_slot_options o on o.slot_id = p.slot_id and o.team_code = t.code
          order by t.ord
       ),
       null
  from power_ballots b
  join power_posts p on p.n = b.n;

insert into private.prompt_slot_answers (slot_id, correct_option_ids)
values ('00000000-0000-0000-0000-00000000b601', array['00000000-0000-0000-0000-00000000c602'::uuid]);

insert into private.prompt_slot_answers (slot_id, correct_option_ids)
select slot_id, array[case winner when 'A' then away_option else home_option end]
  from wk1_games;

insert into public.prompt_comments (id, post_id, author_id, body, posted_with_pick, parent_comment_id, created_at)
values
  ('00000000-0000-0000-0000-00000000e201', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d001', 'Kansas City at home in Week 1 was too much to pass up. The fourth quarter sealed it.', true, null, now() - interval '5 days 2 hours'),
  ('00000000-0000-0000-0000-00000000e202', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d003', 'I thought Denver would carry last season’s momentum into Arrowhead. Wrong side, but it was a fun sweat.', true, null, now() - interval '5 days 8 hours'),
  ('00000000-0000-0000-0000-00000000e203', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d002', 'Mahomes looked composed after halftime. Chiefs was my easiest call of the opener.', true, null, now() - interval '5 days 4 hours'),
  ('00000000-0000-0000-0000-00000000e204', '00000000-0000-0000-0000-00000000a010', '00000000-0000-0000-0000-00000000d003', 'I had the Bills one spot too high.', false, null, now() - interval '13 days'),
  ('00000000-0000-0000-0000-00000000e205', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d002', 'Denver’s defense kept it close early. The last 15 minutes changed the whole feel of it.', false, '00000000-0000-0000-0000-00000000e202', now() - interval '4 days 20 hours'),
  ('00000000-0000-0000-0000-00000000e206', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d001', 'Exactly. I was relieved to see that one turn into a comfortable finish.', false, '00000000-0000-0000-0000-00000000e203', now() - interval '4 days 18 hours'),
  ('00000000-0000-0000-0000-00000000e207', '00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000d003', 'Fair. I am taking Denver again when they get the rematch at home.', false, '00000000-0000-0000-0000-00000000e202', now() - interval '4 days 12 hours'),
  ('00000000-0000-0000-0000-00000000e301', '00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000d001', 'Went chalk on almost everything and it mostly paid off. The two upsets I missed were the ones I talked myself out of.', true, null, now() - interval '5 days 6 hours'),
  ('00000000-0000-0000-0000-00000000e302', '00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000d003', 'Leaned on home teams coming off a rest week. Divisional games are a coin flip and I just picked with my gut there.', true, null, now() - interval '5 days 1 hour'),
  ('00000000-0000-0000-0000-00000000e303', '00000000-0000-0000-0000-00000000a010', '00000000-0000-0000-0000-00000000d001', 'Ranked on last season’s finish plus who added a real quarterback. The Bills and Chiefs at the top was the easy part; the middle of the pack is chaos.', true, null, now() - interval '13 days 6 hours'),
  ('00000000-0000-0000-0000-00000000e304', '00000000-0000-0000-0000-00000000a010', '00000000-0000-0000-0000-00000000d002', 'Defense first. I put every team with a top-five pass rush above its record, and I’d do it again.', true, null, now() - interval '12 days 20 hours'),
  ('00000000-0000-0000-0000-00000000e305', '00000000-0000-0000-0000-00000000a011', '00000000-0000-0000-0000-00000000d001', 'Moved the teams that looked sharp in the opener up a few spots, and dropped anyone with a banged-up offensive line.', true, null, now() - interval '6 days 6 hours'),
  ('00000000-0000-0000-0000-00000000e306', '00000000-0000-0000-0000-00000000a011', '00000000-0000-0000-0000-00000000d002', 'One week of tape is not a trend, but the Eagles looked like the best team on the field and my list says so.', true, null, now() - interval '6 days 2 hours'),
  ('00000000-0000-0000-0000-00000000e307', '00000000-0000-0000-0000-00000000a011', '00000000-0000-0000-0000-00000000d003', 'Kept the top three from last week and shuffled the bottom ten by point differential. Boring, but it is hard to argue with.', true, null, now() - interval '5 days 22 hours');

commit;
