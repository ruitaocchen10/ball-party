-- Sabotage draft's season, played against a fixed real-world baseline
-- instead of the table's own average roster strength.
--
-- The old baseline (simulate_season, 0056/0058) was `avg(roster_strength)`
-- across the match itself -- every table graded its own curve. That makes a
-- record self-cancelling: whatever the room actually drafted, roughly half
-- the field finishes above .500 and half below, every single match, because
-- the bar moves to match whoever showed up. A table that drafted five
-- genuinely great rosters would still spit out an ordinary spread of
-- records centered on .500, indistinguishable from a table that drafted
-- five mediocre ones.
--
-- The new baseline is a fixed 93, not derived from this match at all.
-- Where it comes from: for every real NFL team-season 2006-2025 in
-- private.av_roster_players, take that team's own actual best player at
-- each of this game's thirteen slots -- its best QB, its best two RBs,
-- three WRs, its best TE/OL/DL/LB/CB/S/ST -- and sum their AV. That's what
-- a genuinely strong, actually-assembled starting lineup was worth, real
-- team by real team, real year by real year. Averaged across all 608
-- team-seasons in the pool, that comes out to 93 (median 92) -- see
-- sabotage_draft_private.baseline_roster_strength's own comment for the
-- number itself.
--
-- Consequence, deliberately: a table where everyone drafts brilliantly can
-- now send everyone home 15-2, and a table where everyone drafts poorly can
-- send everyone home 3-14, because that is what actually happened at the
-- table rather than an artifact of who else was sitting there. Relative
-- ranking inside a match is unaffected either way -- the strongest roster
-- at the table still outranks the second-strongest -- this only changes
-- whether the number attached to that ranking is anchored to .500 or to
-- reality.
create function sabotage_draft_private.baseline_roster_strength()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 93;
$$;

revoke all on function sabotage_draft_private.baseline_roster_strength() from public, anon, authenticated;

-- Restated whole from its current (0058) form, per the append-only rule --
-- the last version on disk is the one this migration must extend. Only the
-- opponent every game is played against changes: `v_mean`, computed from
-- this match's own roster_strength rows, becomes `v_baseline`, the fixed
-- constant above. The `v_mean is null` guard (there's no aggregate left to
-- come back null) becomes an explicit existence check on the same query.
create or replace function sabotage_draft_private.simulate_season(p_match_id uuid, p_seed double precision default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_seed double precision; v_baseline integer; v_player record; v_game int; v_wins smallint;
  v_tie record;
begin
  select coalesce(p_seed, b.seed) into v_seed from sabotage_draft_private.boards b where b.match_id = p_match_id;
  if v_seed is null then raise exception 'board_not_found' using errcode = 'P0001'; end if;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  if not exists (select 1 from sabotage_draft_private.roster_strengths(p_match_id)) then
    raise exception 'incomplete_roster' using errcode = 'P0001';
  end if;
  v_baseline := sabotage_draft_private.baseline_roster_strength();
  for v_player in select * from sabotage_draft_private.roster_strengths(p_match_id) order by user_id loop
    v_wins := 0;
    for v_game in 1 .. 17 loop
      if random() < sabotage_draft_private.win_probability(v_player.roster_strength, v_baseline) then v_wins := v_wins + 1; end if;
    end loop;
    insert into public.sabotage_draft_standings (match_id, user_id, roster_strength, wins, losses, tiebreak_rank)
    values (p_match_id, v_player.user_id, v_player.roster_strength, v_wins, 17 - v_wins, 1);
  end loop;
  insert into sabotage_draft_private.seasons (match_id, seed) values (p_match_id, v_seed);
  -- Table-wide starting rank for every player's win tier: 1 plus however many
  -- other players strictly out-won them. Correct as-is for anyone whose win
  -- count is unique; break_record_tie below only needs to spread the players
  -- who share a tier across that tier's own rank range.
  update public.sabotage_draft_standings s set tiebreak_rank = 1 + (
    select count(*) from public.sabotage_draft_standings o
     where o.match_id = p_match_id and o.wins > s.wins
  ) where s.match_id = p_match_id;
  for v_tie in select wins, array_agg(user_id order by user_id) as players, min(tiebreak_rank) as base_rank
                  from public.sabotage_draft_standings where match_id = p_match_id
                 group by wins having count(*) > 1 loop
    perform sabotage_draft_private.break_record_tie(p_match_id, v_tie.wins, v_tie.players, v_tie.base_rank);
  end loop;
  perform private.finish_match(p_match_id, (
    select jsonb_object_agg(user_id::text, (wins * 1000 + (100 - tiebreak_rank))::numeric)
      from public.sabotage_draft_standings where match_id = p_match_id
  ));
end;
$$;
