-- Portraits reach the sabotage draft client the same way display_name
-- already does: copied at the moment a name becomes visible, never read
-- live off the pool. 0065/0066 supply the join; this migration only wires
-- it into the three places a player's identity already flows through --
-- the options list, a hand-picked pick, and the timeout auto-pick.
--
-- Bodies below are restated whole from their current (0063) form, not from
-- their original (0052) one, per the append-only rule -- the last version
-- on disk is the one this migration must extend.

-- The picker's own read: eligible names for this round, now with a portrait
-- to go with each. A player missing one (0.6% of the pool, per 0066's build
-- output) simply carries a null headshot_url -- the client already has to
-- handle "no photo" for any player, so this is not a new case for it.
drop function if exists sabotage_draft.options(uuid, uuid);

create function sabotage_draft.options(p_match_id uuid, p_target_user_id uuid default null)
returns table (player_id text, display_name text, season smallint, slot_category text, headshot_url text)
language plpgsql stable security definer set search_path = '' as $$
declare v_round public.sabotage_draft_rounds; v_target uuid; v_franchise text;
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  v_target := coalesce(p_target_user_id, auth.uid());
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_target) then
    raise exception 'invalid_target' using errcode = 'P0001';
  end if;
  select r.* into v_round from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r on r.match_id=m.match_id and r.round_number=m.current_round
    where m.match_id=p_match_id;
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_round.round_number, v_target);
  return query
    select p.player_id, p.display_name, p.season, p.slot_category, h.headshot_url
      from private.av_roster_players p
      left join private.av_player_headshots h on h.player_id = p.player_id
     where p.franchise_code=v_franchise
       and p.slot_category=any(sabotage_draft_private.pool_categories(v_round.slot))
     order by p.display_name, p.season;
end;
$$;

revoke all on function sabotage_draft.options(uuid, uuid) from public, anon;
grant execute on function sabotage_draft.options(uuid, uuid) to authenticated;

-- The client-visible pick row. Nullable, unlike display_name and season:
-- those are never absent for a real pool player, but a portrait can be.
alter table public.sabotage_draft_picks add column headshot_url text;

-- The timeout path's random draw gains the same column its hand-picked
-- sibling gets from the pool join below, straight from the same join.
drop function if exists sabotage_draft_private.random_pick(text, text[]);

create function sabotage_draft_private.random_pick(
  p_franchise_code text,
  p_categories text[],
  out player_id text,
  out display_name text,
  out season smallint,
  out headshot_url text
)
language sql
security definer
set search_path = ''
as $$
  select r.player_id, r.display_name, r.season, h.headshot_url
    from private.av_roster_players r
    left join private.av_player_headshots h on h.player_id = r.player_id
   where r.franchise_code = p_franchise_code
     and r.slot_category = any(p_categories)
   order by random()
   limit 1;
$$;

-- Dropping and recreating random_pick makes it a new object, and Postgres
-- grants EXECUTE on a new function to PUBLIC by default — restate 0052's
-- revoke or this quietly reopens the timeout draw to every authenticated
-- user, the exact thing 0052's own leak test (0052_sabotage_draft_picks,
-- "the engine schema stays private") checks for.
revoke all on function sabotage_draft_private.random_pick(text, text[]) from public, anon, authenticated;

-- The hand-picked path, restated whole from 0063: display_name is already
-- re-read from the pool rather than trusted from the arguments, so the
-- portrait join sits right beside it for the same reason -- one read of the
-- pool, not a second source that could disagree.
create or replace function sabotage_draft.submit_pick(
  p_match_id uuid, p_player_id text, p_season smallint
)
returns public.sabotage_draft_picks
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches;
  v_round public.sabotage_draft_rounds; v_active uuid; v_pick public.sabotage_draft_picks;
  v_name text; v_headshot text;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501'; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  if v_user <> v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;
  if v_board.turn_deadline is null or v_board.turn_deadline <= now() then raise exception 'turn_closed' using errcode = 'P0001'; end if;
  if sabotage_draft_private.has_picked(p_match_id, v_board.current_round, v_user) then raise exception 'already_picked' using errcode = 'P0001'; end if;

  select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
  select p.display_name, h.headshot_url into v_name, v_headshot
    from private.av_roster_players p
    left join private.av_player_headshots h on h.player_id = p.player_id
   where p.franchise_code = sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_user)
     and p.player_id = p_player_id and p.season = p_season
     and p.slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
  if not found then raise exception 'invalid_pick' using errcode = 'P0001'; end if;

  insert into public.sabotage_draft_picks (match_id, round_number, user_id, player_id, display_name, season, by_timeout, headshot_url)
  values (p_match_id, v_board.current_round, v_user, p_player_id, v_name, p_season, false, v_headshot) returning * into v_pick;
  insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id) values (p_match_id, v_board.current_round, v_user);

  if sabotage_draft_private.turn_complete(p_match_id, v_board.current_round, v_user) then
    perform sabotage_draft_private.resolve_turn(p_match_id);
  end if;

  return v_pick;
end;
$$;

-- The timeout path, restated whole from 0063: same insert, sourced from
-- random_pick's now-wider row.
create or replace function sabotage_draft_private.expire(p_match_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_active uuid; v_drawn record;
begin
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then return false; end if;
  if v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);

  if not sabotage_draft_private.has_picked(p_match_id, v_board.current_round, v_active) then
    select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
    select * into v_drawn from sabotage_draft_private.random_pick(
      sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_active),
      sabotage_draft_private.pool_categories(v_round.slot)
    );
    if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
    insert into public.sabotage_draft_picks (match_id, round_number, user_id, player_id, display_name, season, by_timeout, headshot_url)
    values (p_match_id, v_board.current_round, v_active, v_drawn.player_id, v_drawn.display_name, v_drawn.season, true, v_drawn.headshot_url);
    insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id) values (p_match_id, v_board.current_round, v_active);
  end if;

  perform sabotage_draft_private.resolve_turn(p_match_id);
  return true;
end;
$$;
