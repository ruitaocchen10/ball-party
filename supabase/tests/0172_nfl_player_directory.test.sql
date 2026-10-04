-- Tests for the player directory (0172): roster ingestion is idempotent and
-- skips released players, and prompts.search_players is open to signed-in
-- non-guest users only, matches names the way the picker needs, and returns
-- card-safe fields.

begin;
select plan(15);
\ir support/harness.psql

insert into tests.fx (k, v) values ('alice', tests.mkuser('alice'));

create function tests.roster_csv(p_rows text) returns text
language sql as $$
  select 'season,team,position,status,full_name,gsis_id,headshot_url' || E'\n' || p_rows;
$$;

create function tests.as_guest(p_id uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_id::text, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

select is(
  prompts_private.sync_nfl_players(tests.roster_csv(
    '2026,KC,QB,ACT,Patrick Mahomes,00-0033873,"https://img/mahomes.png"' || E'\n' ||
    '2026,SF,DL,ACT,Nick Bosa,00-0035710,"https://img/bosa.png"' || E'\n' ||
    '2026,LAR,K,ACT,Joshua Karty,00-0038001,' || E'\n' ||
    '2026,NO,WR,RES,José Ramírez,00-0040001,' || E'\n' ||
    '2026,DAL,LB,DEV,Jose Smith,00-0040002,' || E'\n' ||
    '2026,DEN,QB,ACT,Bo Nix,00-0040005,' || E'\n' ||
    '2026,NYG,WR,ACT,Deebo Samuel,00-0040006,' || E'\n' ||
    '2026,DAL,DB,CUT,Cut Player,00-0040003,' || E'\n' ||
    '2026,DAL,DB,RET,Retired Player,00-0040004,')),
  7, 'a load keeps rostered players of every position and skips CUT and RET');

select is(
  prompts_private.sync_nfl_players(tests.roster_csv(
    '2026,KC,QB,ACT,Patrick Mahomes,00-0033873,"https://img/mahomes.png"' || E'\n' ||
    '2026,SF,DL,ACT,Nick Bosa,00-0035710,"https://img/bosa.png"' || E'\n' ||
    '2026,LAR,K,ACT,Joshua Karty,00-0038001,' || E'\n' ||
    '2026,NO,WR,RES,José Ramírez,00-0040001,' || E'\n' ||
    '2026,DAL,LB,DEV,Jose Smith,00-0040002,' || E'\n' ||
    '2026,DEN,QB,ACT,Bo Nix,00-0040005,' || E'\n' ||
    '2026,NYG,WR,ACT,Deebo Samuel,00-0040006,')),
  7, 'loading the same file again is idempotent');

select is((select count(*)::int from prompts_private.nfl_players), 7, 'and leaves no duplicates');

select tests.act_as((select v from tests.fx where k = 'alice'));

select is(
  (select array_agg(display_name order by display_name) from prompts.search_players('mahomes')),
  array['Patrick Mahomes'], 'a signed-in non-admin can search by last name');

select is(
  (select team from prompts.search_players('patrick maho')), 'KC',
  'every word of the query must match, in any order');

select is(
  (select display_name from prompts.search_players('PATRICK')), 'Patrick Mahomes',
  'search ignores case');

select is(
  (select array_agg(display_name order by display_name) from prompts.search_players('jose')),
  array['José Ramírez', 'Jose Smith'], 'search ignores diacritics in both directions');

select is(
  (select array_agg(display_name order by display_name) from prompts.search_players('ramirez')),
  array['José Ramírez'], 'an unaccented query finds an accented name');

select is(
  (select array_agg(display_name) from prompts.search_players('bo')),
  array['Bo Nix', 'Nick Bosa', 'Deebo Samuel'],
  'ranking: name prefix, then word prefix, then substring');

select is(
  (select status from prompts.search_players('ramirez')), 'RES',
  'a reserve-list player is searchable and carries a status');

select is((select count(*)::int from prompts.search_players('   ')), 0, 'a blank query returns nothing');
select is((select count(*)::int from prompts.search_players('100%')), 0, 'LIKE wildcards in the query are literal');

select tests.as_guest((select v from tests.fx where k = 'alice'));
select throws_ok($$ select * from prompts.search_players('mahomes') $$, '42501', 'not_authorized', 'a guest session is refused');

select tests.act_as_admin();
select ok(
  not has_table_privilege('authenticated', 'prompts_private.nfl_players', 'SELECT'),
  'the directory table itself is not readable by clients');

select ok(
  not has_function_privilege('anon', 'prompts.search_players(text, integer)', 'EXECUTE'),
  'anon cannot execute the search');

select * from finish();
rollback;
