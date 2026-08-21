-- Endless solo Higher or Lower (issue #33).
--
-- A solo ladder cannot be dealt all at once: its length is determined by the
-- player's calls, while a group board retains its fixed main ladder and spare
-- cards for sudden death.  Card selection therefore becomes one reusable
-- operation, used both to build the fixed board and to append one solo card.

create function higher_or_lower_private.prepare_deck(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_board public.higher_or_lower_matches;
begin
  select * into v_board
    from public.higher_or_lower_matches where match_id = p_match_id;

  drop table if exists pg_temp.higher_or_lower_deck;
  create temporary table higher_or_lower_deck on commit drop as
  select d.player_id,
         d.display_name,
         d.position,
         d.season,
         d.team,
         d.week,
         d.opponent,
         d.points,
         percent_rank() over (order by d.points) as quantile,
         h.headshot_url
    from (
      select s.player_id, s.display_name, s.position, s.season, s.team,
             null::smallint as week, null::text as opponent, s.points
        from private.player_seasons s
       where v_board.scoring_mode = 'season_total'
         and s.season between v_board.season_from and v_board.season_to
      union all
      select w.player_id, w.display_name, w.position, w.season, w.team,
             w.week, w.opponent, w.points
        from private.player_weeks w
       where v_board.scoring_mode = 'weekly'
         and w.season between v_board.season_from and v_board.season_to
    ) d
    left join private.player_headshots h on h.player_id = d.player_id;
end;
$$;

-- Deals one ordinal from a prepared deck.  `false` is the ordinary exhaustion
-- result for an endless solo run; an initial fixed board still treats it as a
-- bad input pool and raises from its caller.
create function higher_or_lower_private.deal_next_card(
  p_match_id uuid,
  p_ordinal smallint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_band_min double precision;
  v_band_max double precision;
  v_min double precision;
  v_max double precision;
  v_widen int;
  v_above boolean;
  v_below boolean;
  v_take_above boolean;
  v_anchor double precision;
  v_card record;
  v_used text[];
begin
  select coalesce(array_agg(player_id), '{}') into v_used
    from public.higher_or_lower_cards where match_id = p_match_id;

  if p_ordinal = 0 then
    select d.* into v_card
      from pg_temp.higher_or_lower_deck d
     where d.quantile between 0.35 and 0.65
     order by random()
     limit 1;
  else
    select quantile into v_anchor
      from higher_or_lower_private.answers
     where match_id = p_match_id and ordinal = p_ordinal - 1;

    if v_anchor is null then
      raise exception 'missing_anchor' using errcode = 'P0001';
    end if;

    select b.band_min, b.band_max into v_band_min, v_band_max
      from higher_or_lower_private.band(p_ordinal) b;

    v_widen := 0;
    loop
      v_min := greatest(v_band_min - v_widen * 0.05::double precision, 0::double precision);
      v_max := least(v_band_max + v_widen * 0.05::double precision, 1::double precision);

      select exists (
        select 1 from pg_temp.higher_or_lower_deck d
         where d.quantile > v_anchor
           and d.quantile - v_anchor between v_min and v_max
           and not (d.player_id = any (v_used))
      ) into v_above;
      select exists (
        select 1 from pg_temp.higher_or_lower_deck d
         where d.quantile < v_anchor
           and v_anchor - d.quantile between v_min and v_max
           and not (d.player_id = any (v_used))
      ) into v_below;

      exit when v_above or v_below;
      v_widen := v_widen + 1;
      if v_widen > 20 then return false; end if;
    end loop;

    v_take_above := case when v_above and v_below then random() < 0.5 else v_above end;
    select d.* into v_card
      from pg_temp.higher_or_lower_deck d
     where not (d.player_id = any (v_used))
       and case when v_take_above
         then d.quantile > v_anchor and d.quantile - v_anchor between v_min and v_max
         else d.quantile < v_anchor and v_anchor - d.quantile between v_min and v_max
       end
     order by random()
     limit 1;
  end if;

  if not found then return false; end if;

  insert into public.higher_or_lower_cards (
    match_id, ordinal, player_id, display_name, position,
    season, team, week, opponent, headshot_url, points, revealed_at
  ) values (
    p_match_id, p_ordinal, v_card.player_id, v_card.display_name, v_card.position,
    v_card.season, v_card.team, v_card.week, v_card.opponent, v_card.headshot_url,
    case when p_ordinal = 0 then v_card.points end,
    case when p_ordinal = 0 then now() end
  );
  insert into higher_or_lower_private.answers (match_id, ordinal, points, quantile)
  values (p_match_id, p_ordinal, v_card.points, v_card.quantile);

  return true;
end;
$$;

-- Rebuilt around deal_next_card so the fixed group board and the endless solo
-- board use precisely the same band, widening and no-repeat rules.
create or replace function higher_or_lower_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null,
  p_scoring_mode text default 'season_total',
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seed double precision := coalesce(p_seed, random());
  v_question_count constant smallint := 12;
  v_spare_count constant smallint := 5;
  v_from smallint;
  v_to smallint;
  v_n int;
  v_i smallint;
  v_last_ordinal smallint;
begin
  if p_scoring_mode not in ('weekly', 'season_total') then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  select r.season_from, r.season_to into v_from, v_to
    from higher_or_lower_private.resolve_season_range(p_season_from, p_season_to) r;

  insert into public.higher_or_lower_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;
  select count(*) into v_n from public.higher_or_lower_players where match_id = p_match_id;
  if v_n < 1 then raise exception 'too_few_players' using errcode = 'P0001'; end if;

  insert into public.higher_or_lower_matches (
    match_id, question_count, spare_count, current_question,
    scoring_mode, season_from, season_to, is_solo
  ) values (
    p_match_id, v_question_count, v_spare_count, 1,
    p_scoring_mode, v_from, v_to, v_n = 1
  );
  insert into higher_or_lower_private.boards (match_id, seed) values (p_match_id, v_seed);

  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;
  perform higher_or_lower_private.prepare_deck(p_match_id);
  -- Spares belong to group sudden death. Solo adds exactly the next card only
  -- after its preceding answer survives, so it starts with the main ladder.
  v_last_ordinal := case when v_n = 1 then v_question_count else v_question_count + v_spare_count end;
  for v_i in 0 .. v_last_ordinal loop
    if not higher_or_lower_private.deal_next_card(p_match_id, v_i::smallint) then
      raise exception 'pool_exhausted' using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

-- Appends the challenger that follows the current anchor.  It is only called
-- while expire holds the match row lock, so the ordinal cannot be dealt twice.
create function higher_or_lower_private.extend_board(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_next smallint;
begin
  select current_question + 1 into v_next
    from public.higher_or_lower_matches where match_id = p_match_id;
  perform higher_or_lower_private.prepare_deck(p_match_id);
  return higher_or_lower_private.deal_next_card(p_match_id, v_next);
end;
$$;

create or replace function higher_or_lower_private.expire(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.higher_or_lower_matches;
  v_top int;
  v_tied int;
  v_alive int;
begin
  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id and mt.status = 'playing'::public.match_status
   for update of hm;
  if not found or v_board.phase_deadline is null or v_board.phase_deadline > now() then return false; end if;

  if v_board.phase = 'board_intro' then
    perform higher_or_lower_private.open_question(p_match_id, 1::smallint);
  elsif v_board.phase = 'call' then
    perform higher_or_lower_private.reveal_question(p_match_id, v_board.current_question);
  elsif v_board.phase = 'reveal' then
    if v_board.is_solo then
      if exists (
        select 1 from public.higher_or_lower_players
         where match_id = p_match_id and current_streak = 0
      ) or not higher_or_lower_private.extend_board(p_match_id) then
        perform higher_or_lower_private.complete_match(p_match_id);
      else
        perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
      end if;
    elsif v_board.current_question >= v_board.question_count then
      select max(best_streak) into v_top from public.higher_or_lower_players where match_id = p_match_id;
      select count(*) into v_tied from public.higher_or_lower_players where match_id = p_match_id and best_streak = v_top;
      if v_tied >= 2 then perform higher_or_lower_private.enter_sudden_death(p_match_id);
      else perform higher_or_lower_private.complete_match(p_match_id); end if;
    else
      perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
    end if;
  elsif v_board.phase = 'sudden_death_call' then
    perform higher_or_lower_private.reveal_sudden_death_round(p_match_id, v_board.current_question);
  elsif v_board.phase = 'sudden_death_reveal' then
    select count(*) into v_alive from public.higher_or_lower_players
     where match_id = p_match_id and sudden_death and eliminated_at is null;
    if v_alive <= 1 or v_board.current_question >= v_board.question_count + v_board.spare_count then
      perform higher_or_lower_private.complete_match(p_match_id);
    else
      perform higher_or_lower_private.open_sudden_death_round(p_match_id, (v_board.current_question + 1)::smallint);
    end if;
  else
    return false;
  end if;
  return true;
end;
$$;

revoke all on function higher_or_lower_private.prepare_deck(uuid) from public, anon, authenticated;
revoke all on function higher_or_lower_private.deal_next_card(uuid, smallint) from public, anon, authenticated;
revoke all on function higher_or_lower_private.extend_board(uuid) from public, anon, authenticated;
