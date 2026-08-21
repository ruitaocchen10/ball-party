-- Weekly PPR uses the same ladder algorithm as season totals; only its deck
-- changes. Rebuild the dealer from its current definition so the one ranking,
-- band, widening and distinct-player path stays shared by both modes.
do $migration$
declare
  definition text;
  old_deck text := $deck$
  select s.player_id,
         s.display_name,
         s.position,
         s.season,
         s.team,
         null::smallint as week,
         null::text     as opponent,
         s.points,
         percent_rank() over (order by s.points) as quantile,
         -- Left join in spirit, as in 0013: a player the headshot table has not
         -- caught up with still deals a perfectly good card, with an empty band.
         h.headshot_url
    from private.player_seasons s
    left join private.player_headshots h on h.player_id = s.player_id
   where s.season between v_from and v_to;$deck$;
  new_deck text := $deck$
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
       where p_scoring_mode = 'season_total' and s.season between v_from and v_to
      union all
      select w.player_id, w.display_name, w.position, w.season, w.team,
             w.week, w.opponent, w.points
        from private.player_weeks w
       where p_scoring_mode = 'weekly' and w.season between v_from and v_to
    ) d
    left join private.player_headshots h on h.player_id = d.player_id;$deck$;
begin
  select pg_get_functiondef(
    'higher_or_lower_private.deal_board(uuid,double precision,text,smallint,smallint)'::regprocedure
  ) into definition;

  definition := replace(
    definition,
    $$  if p_scoring_mode = 'weekly' then
    -- The column and the card fields are here; the deck is not. Weekly is #29.
    raise exception 'scoring_mode_not_supported' using errcode = 'P0001';
  elsif p_scoring_mode is distinct from 'season_total' then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;$$,
    $$  if p_scoring_mode not in ('weekly', 'season_total') then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;$$
  );
  definition := replace(definition, old_deck, new_deck);
  execute definition;
end;
$migration$;

create or replace function higher_or_lower.start(
  p_match_id uuid,
  p_scoring_mode text default 'season_total',
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns higher_or_lower.board
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode not in ('weekly', 'season_total') then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  perform higher_or_lower_private.resolve_season_range(p_season_from, p_season_to);
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'higher_or_lower' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform higher_or_lower_private.deal_board(p_match_id, null, p_scoring_mode, p_season_from, p_season_to);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  update public.higher_or_lower_matches set phase = 'board_intro', phase_deadline = now() + interval '5 seconds'
   where match_id = p_match_id;
  return higher_or_lower_private.board_of(p_match_id);
end;
$$;
