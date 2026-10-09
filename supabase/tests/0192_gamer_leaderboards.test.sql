begin;
select plan(24);

\ir support/harness.psql

-- Seed data has finished matches and solo bests of its own; start from none.
delete from public.matches;
delete from public.runs;
delete from public.higher_or_lower_player_stats;
delete from public.qb_season_builder_player_stats;

insert into tests.fx (k, v) values
  ('a',     tests.mkuser('GlA')),
  ('b',     tests.mkuser('GlB')),
  ('c',     tests.mkuser('GlC')),
  ('guest', tests.mkguest('GlGuest'));

-- ---------------------------------------------------------------- fixtures --
-- Runs: r1, r2, r4, r6 and r7 arcade, r3 party, r8 solo. Every run has one match, m<N>, and the players listed below.
insert into public.lobbies (id, code, host_id)
values ('50000000-0000-0000-0000-000000000001', 'GLB01', (select v from tests.fx where k = 'a'));

insert into public.runs (id, lobby_id, mode, status, started_at, ended_at)
select ('30000000-0000-0000-0000-00000000000' || n)::uuid,
       case when mode = 'solo' then null else '50000000-0000-0000-0000-000000000001'::uuid end,
       mode::public.run_mode, 'finished',
       now() - interval '3 hours', now() - interval '2 hours'
  from (values (1, 'arcade'), (2, 'arcade'), (3, 'party'), (4, 'arcade'),
               (6, 'arcade'), (7, 'arcade'), (8, 'solo')) as r(n, mode);

-- m1: a 1st, b 2nd.   m2: a 1st, b 2nd.   m3: b 1st, a 2nd, c 3rd (party).
-- m4: a and c tie for 1st, b 3rd.   m6: b 1st, a 2nd, 40 days ago.
-- m7: a alone (not solo mode).   m8: a alone, solo run.
insert into public.matches (id, run_id, game, seq, status, started_at, ended_at)
select ('40000000-0000-0000-0000-00000000000' || n)::uuid,
       ('30000000-0000-0000-0000-00000000000' || n)::uuid,
       'higher_or_lower', 1, 'complete',
       now() - ago - interval '1 hour', now() - ago
  from (values (1, interval '2 hours'), (2, interval '2 hours'), (3, interval '2 hours'),
               (4, interval '2 hours'), (6, interval '40 days'), (7, interval '2 hours'),
               (8, interval '2 hours')) as m(n, ago);

create function tests.seat(p_n int, p_user text, p_place int) returns void
language sql as $$
  insert into public.run_participants (run_id, user_id, seat)
  select ('30000000-0000-0000-0000-00000000000' || p_n)::uuid, v,
         (select count(*) from public.run_participants
           where run_id = ('30000000-0000-0000-0000-00000000000' || p_n)::uuid)::int
    from tests.fx where k = p_user;
  insert into public.match_players (match_id, run_id, user_id, placement, raw_score)
  select ('40000000-0000-0000-0000-00000000000' || p_n)::uuid,
         ('30000000-0000-0000-0000-00000000000' || p_n)::uuid, v, p_place, 10 - p_place
    from tests.fx where k = p_user;
$$;

select tests.seat(1, 'a', 1); select tests.seat(1, 'b', 2);
select tests.seat(2, 'a', 1); select tests.seat(2, 'b', 2);
select tests.seat(3, 'b', 1); select tests.seat(3, 'a', 2); select tests.seat(3, 'c', 3);
select tests.seat(4, 'a', 1); select tests.seat(4, 'c', 1); select tests.seat(4, 'b', 3);
select tests.seat(6, 'b', 1); select tests.seat(6, 'a', 2);
select tests.seat(7, 'a', 1);
select tests.seat(8, 'a', 1);

-- Lifetime:  a 3 wins / 5 games, b 2 / 5, c 1 / 2.   (m7 and m8 never count)
-- Last week: a 3 / 4,            b 1 / 4, c 1 / 2.   (m6 is 40 days old)

insert into public.higher_or_lower_player_stats (user_id, all_time_high) values
  ((select v from tests.fx where k = 'a'), 7),
  ((select v from tests.fx where k = 'b'), 7),
  ((select v from tests.fx where k = 'c'), 3),
  ((select v from tests.fx where k = 'guest'), 99);
insert into public.qb_season_builder_player_stats (user_id, mode, best_score) values
  ((select v from tests.fx where k = 'a'), 'visible', 80.5),
  ((select v from tests.fx where k = 'b'), 'visible', 91.0),
  ((select v from tests.fx where k = 'b'), 'hidden', 60.0);

select tests.act_as((select v from tests.fx where k = 'a'));

-- ---------------------------------------------------------- multiplayer wins --
select is(
  (select array_agg(display_name || ':' || wins || '/' || games_played order by rank, display_name)
     from public.gamer_leaderboard('lifetime')),
  array['GlA:3/5', 'GlB:2/5', 'GlC:1/2'],
  'lifetime wins and games played, solo and one-player matches excluded'
);
select is(
  (select array_agg(rank order by rank, display_name) from public.gamer_leaderboard('lifetime')),
  array[1, 2, 3],
  'ranks follow wins'
);
select is(
  (select array_agg(display_name || ':' || wins || '/' || games_played order by rank, display_name)
     from public.gamer_leaderboard('week')),
  array['GlA:3/4', 'GlB:1/4', 'GlC:1/2'],
  'the week window leaves out the 40-day-old match'
);
select is(
  (select wins from public.gamer_leaderboard('lifetime') where display_name = 'GlC'),
  1,
  'a tie for first gives each tied player the win'
);
select is(
  (select count(*)::int from public.gamer_leaderboard('lifetime') where display_name = 'GlGuest'),
  0,
  'a guest never ranks'
);
select ok((select is_me from public.gamer_leaderboard('lifetime') where display_name = 'GlA'), 'the caller is flagged');
select is((select max(ranked_count) from public.gamer_leaderboard('lifetime')), 3, 'ranked_count is the board size');
select is((select count(*)::int from public.gamer_leaderboard('lifetime', 2)), 2, 'the limit applies');
select is(
  (select username from public.gamer_leaderboard('lifetime') where display_name = 'GlB'),
  'GlB',
  'a row carries the player''s username'
);

select is(
  (select row(status, rank, wins, games_played, ranked_count, min_wins)::text from public.my_gamer_standing('lifetime')),
  '(ranked,1,3,5,3,1)',
  'my_gamer_standing for a ranked caller'
);

select tests.act_as((select v from tests.fx where k = 'guest'));
select is(
  (select row(status, wins, games_played)::text from public.my_gamer_standing('lifetime')),
  '(unranked,0,0)',
  'a caller with no wins is unranked'
);
select throws_ok($$select * from public.gamer_leaderboard('friends-of')$$, '22023', 'invalid_window', 'a bad window is refused');
select throws_ok($$select * from public.gamer_leaderboard('week', 50, 'friends')$$, null, null, 'a guest has no friends board');

-- ------------------------------------------------------------- friends scope --
select tests.act_as((select v from tests.fx where k = 'c'));
select public.send_friend_request('GlA');
select tests.act_as((select v from tests.fx where k = 'a'));
select public.accept_friend_request((select v from tests.fx where k = 'c'));
select is(
  (select array_agg(display_name || ':' || rank order by rank, display_name) from public.gamer_leaderboard('lifetime', 50, 'friends')),
  array['GlA:1', 'GlC:2'],
  'the friends board is the caller plus friends, ranked among themselves'
);

-- --------------------------------------------------------------- solo boards --
select is(
  (select array_agg(display_name || ':' || best_score::int || ':' || rank order by rank, display_name)
     from public.solo_leaderboard('higher_or_lower')),
  array['GlA:7:1', 'GlB:7:1', 'GlC:3:3'],
  'Higher or Lower ranks best streaks, ties share a rank, guests are left out'
);
select is(
  (select array_agg(display_name || ':' || best_score order by rank) from public.solo_leaderboard('qb_season_builder', 'visible')),
  array['GlB:91.0', 'GlA:80.5'],
  'QB visible ranks best scores'
);
select is(
  (select array_agg(display_name order by rank) from public.solo_leaderboard('qb_season_builder', 'hidden')),
  array['GlB'],
  'QB hidden is its own board'
);
select is(
  (select array_agg(display_name || ':' || rank order by rank, display_name) from public.solo_leaderboard('higher_or_lower', null, 50, 'friends')),
  array['GlA:1', 'GlC:2'],
  'solo friends scope'
);
select is(
  (select row(status, rank, best_score, ranked_count)::text from public.my_solo_standing('qb_season_builder', 'visible')),
  '(ranked,2,80.5,2)',
  'my_solo_standing for a ranked caller'
);
select is(
  (select row(status, rank, best_score)::text from public.my_solo_standing('qb_season_builder', 'hidden')),
  '(unranked,,)',
  'no best on a board means unranked with a null best'
);
select throws_ok($$select * from public.solo_leaderboard('nope')$$, '22023', 'invalid_game', 'an unknown game is refused');
select throws_ok($$select * from public.solo_leaderboard('qb_season_builder')$$, '22023', 'invalid_mode', 'QB needs a mode');
select throws_ok($$select * from public.solo_leaderboard('higher_or_lower', 'visible')$$, '22023', 'invalid_mode', 'Higher or Lower takes no mode');

select tests.act_as_admin();
select ok(
  has_function_privilege('authenticated', 'public.gamer_leaderboard(text,integer,text)', 'execute')
    and has_function_privilege('authenticated', 'public.solo_leaderboard(text,text,integer,text)', 'execute')
    and not has_function_privilege('anon', 'public.gamer_leaderboard(text,integer,text)', 'execute')
    and not has_function_privilege('anon', 'public.solo_leaderboard(text,text,integer,text)', 'execute'),
  'only signed-in players can call the boards'
);

select * from finish();
rollback;
