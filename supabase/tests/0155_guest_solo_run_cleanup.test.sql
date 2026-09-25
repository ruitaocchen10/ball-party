-- Tests for the nightly guest cleanup once guests can play solo (migration 0155).
--
-- Runs are aged by moving the run's own timestamps back, the way the game would
-- have written them a while ago, and the cleanup is then called directly, as
-- cron does. Four kinds of player: a guest whose runs are all past their
-- lifetime, a guest with an old identity but a recent run, a guest that also took
-- part in a party match, and a real account with an old unfinished solo run.

begin;
select plan(13);

\ir support/harness.psql

insert into tests.fx (k, v)
values ('stale', tests.mkguest('sam')),
       ('returning', tests.mkguest('rae')),
       ('party', tests.mkguest('pat')),
       ('account', tests.mkuser('ava'));

-- Old enough for the account-age rule in 0016 to be met by every guest.
update auth.users set created_at = now() - interval '45 days'
 where id in (select v from tests.fx where k in ('stale', 'returning', 'party'));

-- ---------------------------------------------------------------------- stale --

-- A finished QB run, an unfinished QB run and a Higher or Lower run.
insert into tests.fx (k, v) select 'stale_done', tests.qsb_start((select v from tests.fx where k = 'stale'), 'visible', true);
select tests.qsb_fill((select v from tests.fx where k = 'stale_done'), 6);
select qb_season_builder.finish((select v from tests.fx where k = 'stale_done'));
insert into tests.fx (k, v) select 'stale_open', tests.qsb_start((select v from tests.fx where k = 'stale'), 'hidden', true);
insert into tests.fx (k, v) select 'stale_hol', id from public.start_solo_run('higher_or_lower');
select higher_or_lower.start((select v from tests.fx where k = 'stale_hol'));

-- ------------------------------------------------------------------ returning --

-- Finished five days ago, an unfinished run from two hours ago, and one from
-- three days ago that nobody will come back to.
insert into tests.fx (k, v) select 'ret_done', tests.qsb_start((select v from tests.fx where k = 'returning'), 'visible', true);
select tests.qsb_fill((select v from tests.fx where k = 'ret_done'), 6);
select qb_season_builder.finish((select v from tests.fx where k = 'ret_done'));
insert into tests.fx (k, v) select 'ret_recent', tests.qsb_start((select v from tests.fx where k = 'returning'), 'visible', true);
insert into tests.fx (k, v) select 'ret_old', tests.qsb_start((select v from tests.fx where k = 'returning'), 'visible', true);

-- ------------------------------------------------------------------- an account --

insert into tests.fx (k, v) select 'acct_open', tests.mksolomatch((select v from tests.fx where k = 'account'), 'higher_or_lower');

-- ---------------------------------------------------------------------- a party --

-- A room of real players, plus a guest seated in its run: the state a guest that
-- was carried into a party before 0113 stopped that is left in.
insert into tests.fx (k, v) select 'party_match', tests.mkmatch(2, 'higher_or_lower');
select tests.act_as_admin();
insert into public.run_participants (run_id, user_id, seat)
values ((select run_id from public.matches where id = (select v from tests.fx where k = 'party_match')),
        (select v from tests.fx where k = 'party'), 3);

-- ----------------------------------------------------------------- age the runs --

reset role;

-- Moves a match's run back in time, and its end with it when it has one.
create function pg_temp.age(p_key text, p_started interval, p_ended interval default null) returns void
language sql as $$
  update public.runs
     set started_at = now() - p_started
   where id = (select run_id from public.matches where id = (select v from tests.fx where k = p_key));
  update public.matches
     set ended_at = case when p_ended is null then ended_at else now() - p_ended end
   where id = (select v from tests.fx where k = p_key);
  update public.runs
     set ended_at = case when p_ended is null then ended_at else now() - p_ended end
   where id = (select run_id from public.matches where id = (select v from tests.fx where k = p_key));
$$;

select pg_temp.age('stale_done', interval '40 days', interval '31 days');
select pg_temp.age('stale_open', interval '2 days');
select pg_temp.age('stale_hol', interval '2 days');
select pg_temp.age('ret_done', interval '6 days', interval '5 days');
select pg_temp.age('ret_recent', interval '2 hours');
select pg_temp.age('ret_old', interval '3 days');
select pg_temp.age('acct_open', interval '40 days');

select lives_ok($$ select private.cleanup_guest_accounts() $$, 'the cleanup runs');
select lives_ok($$ select private.cleanup_guest_accounts() $$, 'and can run again with nothing left to do');

-- ---------------------------------------------------------------------- checks --

select is(
  (select count(*)::int from public.matches
    where id in (select v from tests.fx where k in ('stale_done', 'stale_open', 'stale_hol'))),
  0,
  'a guest''s finished run past 30 days and unfinished runs past a day are gone, in either game'
);
select is(
  (select count(*)::int from qb_season_builder_private.season_results
    where match_id = (select v from tests.fx where k = 'stale_done')),
  0,
  'and so is the saved season, which lives on the match'
);
select is(
  (select count(*)::int from auth.users where id = (select v from tests.fx where k = 'stale')),
  0,
  'a guest with nothing left is removed too, profile and all'
);
select is(
  (select count(*)::int from public.profiles where id = (select v from tests.fx where k = 'stale')),
  0,
  'the profile with it'
);

select is(
  (select count(*)::int from public.matches
    where id in (select v from tests.fx where k in ('ret_done', 'ret_recent'))),
  2,
  'a returning guest keeps a run finished within 30 days and one started within a day'
);
select is(
  (select count(*)::int from public.matches where id = (select v from tests.fx where k = 'ret_old')),
  0,
  'but not the unfinished one from three days ago'
);
select is(
  (select count(*)::int from qb_season_builder_private.season_results
    where match_id = (select v from tests.fx where k = 'ret_done')),
  1,
  'so its recent shared result still works'
);
select is(
  (select count(*)::int from auth.users where id = (select v from tests.fx where k = 'returning')),
  1,
  'and an old identity with a recent run is not removed, whatever its age'
);

select is(
  (select count(*)::int from public.matches where id = (select v from tests.fx where k = 'party_match')),
  1,
  'a party match is not touched'
);
select is(
  (select count(*)::int from auth.users where id = (select v from tests.fx where k = 'party')),
  1,
  'and a guest that took part in one keeps its identity'
);
select is(
  (select count(*)::int from public.matches where id = (select v from tests.fx where k = 'acct_open')),
  1,
  'a real account''s old unfinished solo run is never touched'
);

select * from finish();
rollback;
