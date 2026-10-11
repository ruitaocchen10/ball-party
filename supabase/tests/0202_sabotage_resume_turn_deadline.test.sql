-- Resuming a paused Sabotage Draft shifts its turn clock by the time spent paused.
-- resume_match used to shift two columns the table no longer has, so the host's
-- Resume raised 42703 and the match stayed paused.
begin;
select plan(4);
\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.mkmatch(4, 'sabotage_draft'));
select sabotage_draft.start((select v from tests.fx where k = 'm'));
select tests.act_as_admin();
insert into tests.fx (k, v)
select 'host', host_id from public.lobbies where id = (
  select lobby_id from public.runs where id = (select run_id from public.matches where id = (select v from tests.fx where k = 'm')));

select tests.act_as((select v from tests.fx where k = 'host'));
select public.pause_match((select v from tests.fx where k = 'm'));
select is((select status::text from public.matches where id = (select v from tests.fx where k = 'm')), 'paused', 'the host can pause');

-- Pretend the table sat paused for a minute, and note where the turn clock was.
select tests.act_as_admin();
update public.matches set paused_at = now() - interval '1 minute' where id = (select v from tests.fx where k = 'm');
create temp table before_deadline as
  select turn_deadline from public.sabotage_draft_matches where match_id = (select v from tests.fx where k = 'm');

select tests.act_as((select v from tests.fx where k = 'host'));
select lives_ok(format($$ select public.resume_match(%L) $$, (select v from tests.fx where k = 'm')), 'the host can resume it');
select tests.act_as_admin();
select is((select status::text from public.matches where id = (select v from tests.fx where k = 'm')), 'playing', 'and it is playing again');
select ok(
  (select s.turn_deadline - b.turn_deadline from public.sabotage_draft_matches s, before_deadline b
    where s.match_id = (select v from tests.fx where k = 'm'))
  between interval '59 seconds' and interval '61 seconds',
  'with the turn clock pushed back by the minute it was paused');

select * from finish();
rollback;
