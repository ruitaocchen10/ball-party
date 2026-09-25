-- QB Season Builder: show letter grades instead of the blended values.
--
-- A player still picks against the same six blended values, and the season model
-- still runs on them (pick_values is untouched). What changes is what a client is
-- told: a quality or a Supporting Cast is now a grade, A+ to F, never the number
-- behind it. A grade is coarser than the value, which is the point — it says how
-- good an option is without letting a player add six numbers up.
--
-- The mapping happens here, in the two projections every board is built from
-- (options_of for a dealt spin and its reveal, picks_of for what was taken), so
-- no number is in the payload for a client to read, in either mode. Hidden mode
-- is unchanged: a grade is withheld exactly where a value was.
--
-- The wire keys are renamed rather than reused: `values` -> `grades`, the
-- Supporting Cast's `value` -> `grade`, and a pick's `value` -> `grade`. A letter
-- under a numeric-sounding name would be a trap for the next reader.
--
-- The cut-offs were set against the real spread of what the game deals (every
-- quality of every quarterback-season and every Supporting Cast: 25 to 99, median
-- 61, close to evenly spread), so the grades are five points wide and the median
-- lands on C-:
--
--   A+ 95-99   A 90-94   A- 86-89   B+ 82-85   B 78-81   B- 74-77   C+ 70-73
--   C 65-69    C- 60-64  D+ 55-59   D 50-54    D- 45-49  F 44 and below
--
-- F is the one lump, about a fifth of all values, because it collects the whole
-- tail below 45. Nothing here changes what a value is worth to the season model.

-- ------------------------------------------------------------------ grade_of --

create function qb_season_builder_private.grade_of(p_value integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null then null
    when p_value >= 95 then 'A+'
    when p_value >= 90 then 'A'
    when p_value >= 86 then 'A-'
    when p_value >= 82 then 'B+'
    when p_value >= 78 then 'B'
    when p_value >= 74 then 'B-'
    when p_value >= 70 then 'C+'
    when p_value >= 65 then 'C'
    when p_value >= 60 then 'C-'
    when p_value >= 55 then 'D+'
    when p_value >= 50 then 'D'
    when p_value >= 45 then 'D-'
    else 'F'
  end;
$$;

revoke all on function qb_season_builder_private.grade_of(integer)
  from public, anon, authenticated;

-- --------------------------------------------------------------- the options --

-- 0129's projection with grades where the values were.
create or replace function qb_season_builder_private.options_of(
  p_franchise_code text, p_season smallint, p_reveal boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'quarterbacks', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'player_id',    q.player_id,
                 'display_name', q.display_name,
                 'headshot_url', h.headshot_url,
                 'grades', case when p_reveal then jsonb_build_object(
                   'accuracy',   qb_season_builder_private.grade_of(q.accuracy),
                   'arm_talent', qb_season_builder_private.grade_of(q.arm_talent),
                   'mobility',   qb_season_builder_private.grade_of(q.mobility),
                   'iq',         qb_season_builder_private.grade_of(q.iq),
                   'build',      qb_season_builder_private.grade_of(q.build)
                 ) end
               )
               order by q.player_id
             )
        from qb_season_builder_private.qb_seasons q
        left join private.av_player_headshots h on h.player_id = q.player_id
       where q.franchise_code = p_franchise_code and q.season = p_season
    ), '[]'::jsonb),
    'supporting_cast', jsonb_build_object(
      'grade', (
        select case when p_reveal then qb_season_builder_private.grade_of(t.supporting_cast) end
          from qb_season_builder_private.team_seasons t
         where t.franchise_code = p_franchise_code and t.season = p_season
      )
    )
  );
$$;

-- ----------------------------------------------------------------- the picks --

-- 0130's projection with a grade where the value was.
create or replace function qb_season_builder_private.picks_of(p_match_id uuid, p_reveal boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'round',          p.round_number,
             'slot',           p.slot,
             'franchise_code', p.franchise_code,
             'season',         p.season,
             'player_id',      p.player_id,
             'display_name',   p.display_name,
             'grade',          case when p_reveal then qb_season_builder_private.grade_of(pv.value) end
           ) || case when h.headshot_url is null then '{}'::jsonb
                     else jsonb_build_object('headshot_url', h.headshot_url) end
           order by p.round_number
         ), '[]'::jsonb)
    from public.qb_season_builder_picks p
    join qb_season_builder_private.pick_values pv
      on pv.match_id = p.match_id and pv.slot = p.slot
    left join private.av_player_headshots h
      on h.player_id = p.player_id
   where p.match_id = p_match_id;
$$;

-- -------------------------------------------------------------- the result --

-- 0127's result, with the recap's picks re-projected on the way out. A result is
-- stored as the jsonb `finish` returned, so one saved before this migration
-- carries `value` on each pick; it is graded here rather than rewritten in place,
-- which keeps the private table untouched and gives a shared link to an old run
-- the same recap as a new one. A pick that already has a `grade` passes through.
create or replace function qb_season_builder.result(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  select r.result into v_result
    from qb_season_builder_private.season_results r
   where r.match_id = p_match_id;

  if not found then
    raise exception 'result_not_found' using errcode = 'P0002';
  end if;

  return jsonb_set(
    v_result,
    '{picks}',
    coalesce((
      select jsonb_agg(
               case when p.pick ? 'value'
                    then (p.pick - 'value') || jsonb_build_object(
                           'grade', qb_season_builder_private.grade_of((p.pick ->> 'value')::integer))
                    else p.pick end
               order by p.ord
             )
        from jsonb_array_elements(v_result -> 'picks') with ordinality as p(pick, ord)
    ), '[]'::jsonb)
  );
end;
$$;
