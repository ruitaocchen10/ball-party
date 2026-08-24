-- Disconnects add presence state, not a second set of game resolutions.
begin;
select plan(14);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(3, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

select ok(
  (select bool_and(not absent) from public.sabotage_draft_players
    where match_id = (select v from tests.fx where k = 'm')),
  'every seated player starts present'
);
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'sabotage_draft_players'
      and column_name = 'absent'),
  1,
  'absence is one flag on the existing seated-player state'
);

select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(
  format($$ select sabotage_draft.mark_absent(%L) $$, (select v from tests.fx where k = 'm')),
  'a player can mark only their own live seat absent'
);
select tests.act_as_admin();
select ok((select absent from public.sabotage_draft_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'the disconnected seat is visibly latched absent'
);
select is((select count(*)::int from public.sabotage_draft_players
  where match_id = (select v from tests.fx where k = 'm')),
  3, 'absence does not remove the seat or its eventual roster from the match'
);

-- The absent player makes no pick.  Expiry uses 0052's ordinary random draw,
-- then 0053's normal transition opens the guess window.
select tests.sd_expire((select v from tests.fx where k = 'm'));
select ok((select by_timeout from public.sabotage_draft_picks
  where match_id = (select v from tests.fx where k = 'm') and round_number = 1
    and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'an absent player follows the existing random-respin timeout path'
);
select ok((select guess_deadline > now() from public.sabotage_draft_matches
  where match_id = (select v from tests.fx where k = 'm')),
  'the timeout enters the ordinary shared guess window'
);

-- p2 guesses p1's already-locked timeout pick.  The target's absence is not
-- consulted by submit_guess, so this resolves exactly like any other target.
-- Make the test card deterministic after proving the timeout path above; the
-- card is private to p1, so p2 must not read it back to construct the guess.
select tests.act_as_admin();
update public.sabotage_draft_picks p
   set player_id = c.player_id, season = c.season
  from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p1'), 'QB') c
 where p.match_id = (select v from tests.fx where k = 'm') and p.round_number = 1
   and p.user_id = (select v::uuid from tests.fx where k = 'p1');
select tests.act_as((select v from tests.fx where k = 'p2'));
select is(
  (select g.result::text
     from tests.sd_pick_candidate((select v from tests.fx where k = 'm'), 1::smallint, (select v from tests.fx where k = 'p1'), 'QB') c
     cross join lateral sabotage_draft.submit_guess(
       (select v from tests.fx where k = 'm'),
       (select v::uuid from tests.fx where k = 'p1'), c.player_id
     ) g
  ),
  'respun',
  'a guess against an absent player''s locked pick resolves normally'
);

-- p1 spends no guess: no record is required, and expiry advances normally.
select tests.act_as_admin();
update public.sabotage_draft_matches set guess_deadline = now() - interval '1 second'
 where match_id = (select v from tests.fx where k = 'm');
select ok(sabotage_draft_private.expire((select v from tests.fx where k = 'm')),
  'an expired guess window resolves without an absent player guessing');
select is((select count(*)::int from public.sabotage_draft_guesses
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p1')),
  0, 'no guess row is the same pass an absent player defaults to');
select is((select current_round::int from public.sabotage_draft_matches
  where match_id = (select v from tests.fx where k = 'm')),
  2, 'the ordinary guess expiry advances the match');

select tests.act_as((select v from tests.fx where k = 'p1'));
select lives_ok(
  format($$ select sabotage_draft.tick(%L) $$, (select v from tests.fx where k = 'm')),
  'the ordinary clock ping works after reconnecting'
);
select tests.act_as_admin();
select ok((select not absent from public.sabotage_draft_players
  where match_id = (select v from tests.fx where k = 'm') and user_id = (select v::uuid from tests.fx where k = 'p1')),
  'the first ordinary ping clears absence with no rehydration RPC'
);
select ok(has_function_privilege('authenticated', 'sabotage_draft.mark_absent(uuid)', 'EXECUTE'),
  'participants can report their own disconnect through the public API');

select * from finish();
rollback;
