-- Portraits (0065/0066) flow into sabotage draft the same way display_name
-- already does: copied at the moment a pick's identity becomes visible,
-- never read live off the pool. These assertions cover the copy itself --
-- correctness of the join wherever a headshot_url leaves the pool -- not
-- coverage, which scripts/av_roster_pool's own build guard already owns.

begin;
select plan(4);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal_sabotage_draft(2, 0.4));
insert into tests.fx (k, v)
  select 'p' || seat, user_id from public.sabotage_draft_players
   where match_id = (select v from tests.fx where k = 'm') order by seat;
select tests.act_as_admin();
update public.matches set status = 'playing', started_at = now()
 where id = (select v from tests.fx where k = 'm');

-- ------------------------------------------------------------- options() --

-- Every option the picker sees carries whatever the pool join would say for
-- that player -- never a stale or mismatched portrait. A wrong-row copy
-- would leave at least one option's headshot_url `is distinct from` its own
-- player's row in the pool table.
--
-- Captured into a temp table while acting as p0 (options() is security
-- definer, but the comparison join below reads private.av_player_headshots
-- directly, which p0's own `authenticated` session has no grant on -- the
-- same reason 0022's own headshot suite runs its comparison as admin).
select tests.act_as((select v from tests.fx where k = 'p0'));
create temp table opts as
  select * from sabotage_draft.options((select v from tests.fx where k = 'm'));

select tests.act_as_admin();
select is(
  (select count(*)::int
     from opts o
     left join private.av_player_headshots h on h.player_id = o.player_id
    where o.headshot_url is distinct from h.headshot_url),
  0,
  'every option carries its own player''s headshot, not some other row''s'
);

-- --------------------------------------------------------------- the pick --

select tests.act_as_admin();
select sd_pick.player_id as pid, sd_pick.season as yr
  from tests.sd_pick_candidate(
    (select v from tests.fx where k = 'm'), 1::smallint,
    (select v::uuid from tests.fx where k = 'p0'), 'QB'
  ) sd_pick \gset

select tests.act_as((select v from tests.fx where k = 'p0'));
select sabotage_draft.submit_pick((select v from tests.fx where k = 'm'), :'pid', :yr::smallint);

select tests.act_as_admin();
select is(
  (select p.headshot_url is distinct from h.headshot_url
     from public.sabotage_draft_picks p
     left join private.av_player_headshots h on h.player_id = p.player_id
    where p.match_id = (select v from tests.fx where k = 'm')
      and p.round_number = 1 and p.user_id = (select v::uuid from tests.fx where k = 'p0')),
  false,
  'a hand-picked pick carries its own player''s headshot from the pool join'
);

-- ------------------------------------------------------------ the timeout --

-- p1 never picks. One shared clock covers both the active seat's pick and
-- everyone else's guess-or-pass (0063), so the first expiry only resolves
-- p0's own turn and advances the active seat to p1 -- a second is what
-- times out p1's own turn and draws its random replacement, the same two
-- calls 0063's own timeout tests make. That draw has to carry a portrait
-- too, sourced from the same join random_pick now makes.
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.sd_expire((select v from tests.fx where k = 'm'));
select tests.act_as_admin();
select is(
  (select p.headshot_url is distinct from h.headshot_url
     from public.sabotage_draft_picks p
     left join private.av_player_headshots h on h.player_id = p.player_id
    where p.match_id = (select v from tests.fx where k = 'm')
      and p.round_number = 1 and p.user_id = (select v::uuid from tests.fx where k = 'p1')),
  false,
  'a timeout-drawn pick carries its own player''s headshot from the same join'
);

-- ------------------------------------------------------------ the leak --

-- Same posture as every other `private` table (0007, 0013, 0049): no
-- REST-reachable role holds a grant, so a client cannot enumerate the
-- portrait table directly, only ever receive one copied row's worth.
select ok(
  not has_table_privilege('authenticated', 'private.av_player_headshots', 'SELECT')
  and not has_table_privilege('anon', 'private.av_player_headshots', 'SELECT'),
  'the portrait table itself stays unreachable from the client'
);

select * from finish();
rollback;
