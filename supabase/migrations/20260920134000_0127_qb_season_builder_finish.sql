-- QB Season Builder: finishing a run. See issue #77 (sub-issue of #72). The run
-- loop is 0120-0122, the season model 0125-0126.

-- ------------------------------------------------------------- the saved result --

-- One row per finished run, and the only place a generated season lives. Private,
-- like the ratings and the model, for two reasons: the SEED is stored here and no
-- client may ever read it, and the result is served through qb_season_builder.result
-- (a projection) rather than a table a policy has to keep honest.
create table qb_season_builder_private.season_results (
  match_id   uuid        primary key references public.matches (id) on delete cascade,
  seed       bigint      not null,
  mode       text        not null check (mode in ('visible', 'hidden')),
  score      numeric(4, 1) not null check (score between 0 and 100),
  result     jsonb       not null,
  created_at timestamptz not null default now()
);

alter table qb_season_builder_private.season_results enable row level security;
revoke all on table qb_season_builder_private.season_results from public, anon, authenticated;

-- ---------------------------------------------------------- the personal best --

-- One best score per player per mode, so a hidden run is never measured against a
-- visible one. Written only by finish (there is no partial score), and readable
-- only by its owner while signed in with an account, exactly as Higher or Lower's
-- all-time high is (0112). A guest's best is still recorded, against the same
-- user id, so it is there if they later sign up; they simply cannot read it.
create table public.qb_season_builder_player_stats (
  user_id    uuid          not null references public.profiles (id) on delete cascade,
  mode       text          not null check (mode in ('visible', 'hidden')),
  best_score numeric(4, 1) not null check (best_score between 0 and 100),
  updated_at timestamptz   not null default now(),

  primary key (user_id, mode)
);

alter table public.qb_season_builder_player_stats enable row level security;

create policy qb_season_builder_player_stats_select_own
  on public.qb_season_builder_player_stats
  for select to authenticated
  using (auth.uid() = user_id and (auth.jwt() ->> 'is_anonymous')::boolean is not true);

-- Platform defaults hand every client role privileges on a new public table. Take
-- them all back first, so a signed-out client is refused outright rather than
-- merely shown no rows, and only then give a signed-in player the read.
revoke all on table public.qb_season_builder_player_stats from public, anon, authenticated;
grant select on public.qb_season_builder_player_stats to authenticated;

-- ------------------------------------------------------------ the season generator --

-- A uniform draw in [0, 1) that belongs to a seed and a label. Every random thing
-- a season needs (each output's noise, each playoff rung, each award's edge) asks
-- for its own label, so a draw never depends on the order the others were made in
-- and the same seed always gives the same season. It is a hash and not
-- setseed()/random(): setseed would leave the session's random() predictable for
-- whoever shares the connection next, draw_spin included.
create function qb_season_builder_private.unit_draw(p_seed bigint, p_label text)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select (('x' || substr(md5(p_seed::text || ':' || p_label), 1, 8))::bit(32)::bigint)::double precision
         / 4294967296.0;
$$;

-- The real residual of an output at quantile u, interpolated between the two table
-- entries either side of it. The table runs from p = 0 to p = 1, so the answer is
-- always inside what really happened.
create function qb_season_builder_private.residual_at(p_output text, p_u double precision)
returns double precision
language sql
stable
security definer
set search_path = ''
as $$
  select case when hi.p = lo.p then lo.residual
              else lo.residual + (hi.residual - lo.residual) * (p_u - lo.p) / (hi.p - lo.p)
         end
    from (select r.p, r.residual from qb_season_builder_private.season_model_residuals r
           where r.output = p_output and r.p <= p_u order by r.p desc limit 1) lo,
         (select r.p, r.residual from qb_season_builder_private.season_model_residuals r
           where r.output = p_output and r.p >= p_u order by r.p limit 1) hi;
$$;

-- One output of the model for a build: the formula of the six values, plus this
-- output's share of a draw from its real residual spread, through its link.
-- p_values is {"accuracy": n, ...} for all six slots.
create function qb_season_builder_private.output_value(
  p_output text, p_values jsonb, p_seed bigint
)
returns double precision
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_out qb_season_builder_private.season_model_outputs;
  v_z   double precision;
begin
  select * into v_out from qb_season_builder_private.season_model_outputs where output = p_output;

  select v_out.intercept + coalesce(sum(c.coefficient * (p_values ->> c.slot)::double precision), 0)
    into v_z
    from qb_season_builder_private.season_model_coefficients c
   where c.output = p_output;

  v_z := v_z + v_out.noise_scale * qb_season_builder_private.residual_at(
    p_output, qb_season_builder_private.unit_draw(p_seed, 'noise:' || p_output)
  );

  return case v_out.link
    when 'identity' then least(v_out.high, greatest(v_out.low, v_z))
    when 'log'      then least(v_out.high, exp(v_z))
    when 'logit'    then v_out.low + (v_out.high - v_out.low) / (1 + exp(-v_z))
  end;
end;
$$;

-- sum(weight * z-score of the metric) for one of the model's formulas, over the
-- metrics of a season.
create function qb_season_builder_private.metric_formula(p_formula text, p_metrics jsonb)
returns double precision
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(f.weight * ((p_metrics ->> f.term)::double precision - m.mean) / m.sd), 0)
    from qb_season_builder_private.season_model_formulas f
    join qb_season_builder_private.season_model_metrics m on m.metric = f.term
   where f.formula = p_formula;
$$;

-- Turns the six values of a build into a season, from a seed. Pure in the sense
-- that matters: the same values and seed give the same season, and it writes
-- nothing. Rounding is done here: counts to whole numbers, wins rounded with
-- losses the rest of 17.
create function qb_season_builder_private.generate_season(p_values jsonb, p_seed bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_out       jsonb;
  v_attempts  double precision;
  v_comp_pct  double precision;
  v_ypa       double precision;
  v_td_rate   double precision;
  v_int_rate  double precision;
  v_stat      jsonb;
  v_wins      int;
  v_depth     int := 0;
  v_rung      qb_season_builder_private.season_model_playoff_ladder;
  v_award     qb_season_builder_private.season_model_awards;
  v_awards    jsonb := '{}'::jsonb;
  v_metrics   jsonb;
  v_earned    boolean;
  v_composite jsonb;
  v_breakdown jsonb;
  v_score     numeric;
  v_closest   jsonb;
begin
  select jsonb_object_agg(o.output, qb_season_builder_private.output_value(o.output, p_values, p_seed))
    into v_out
    from qb_season_builder_private.season_model_outputs o;

  v_attempts := (v_out ->> 'attempts')::double precision;
  v_comp_pct := (v_out ->> 'comp_pct')::double precision;
  v_ypa      := (v_out ->> 'ypa')::double precision;
  v_td_rate  := (v_out ->> 'td_rate')::double precision;
  v_int_rate := (v_out ->> 'int_rate')::double precision;

  v_stat := jsonb_build_object(
    'attempts',      round(v_attempts::numeric)::int,
    'completions',   round((v_attempts * v_comp_pct)::numeric)::int,
    'pass_yards',    round((v_attempts * v_ypa)::numeric)::int,
    'pass_tds',      round((v_attempts * v_td_rate)::numeric)::int,
    'interceptions', round((v_attempts * v_int_rate)::numeric)::int,
    -- The passer rating formula: four components, each held to [0, 2.375].
    'rating',        round((
        least(2.375, greatest(0, (v_comp_pct - 0.3) * 5))
      + least(2.375, greatest(0, (v_ypa - 3) * 0.25))
      + least(2.375, greatest(0, v_td_rate * 20))
      + least(2.375, greatest(0, 2.375 - v_int_rate * 25))
      )::numeric / 6 * 100, 1),
    'rush_yards',    round((v_out ->> 'rush_yards')::numeric)::int,
    'rush_tds',      round((v_out ->> 'rush_td')::numeric)::int
  );

  v_wins := round((v_out ->> 'wins')::numeric)::int;

  -- The playoff ladder: clear each rung with its chance at this many wins, and stop
  -- at the first one missed. The depth is the number of rungs cleared: 0 missed the
  -- playoffs, 5 won the title.
  for v_rung in
    select * from qb_season_builder_private.season_model_playoff_ladder order by rung
  loop
    exit when qb_season_builder_private.unit_draw(p_seed, 'ladder:' || v_rung.step)
              >= 1 / (1 + exp(-(v_rung.intercept + v_rung.slope * v_wins)));
    v_depth := v_depth + 1;
  end loop;

  v_metrics := jsonb_build_object(
    'pass_yards',    v_stat -> 'pass_yards',
    'pass_td',       v_stat -> 'pass_tds',
    'interceptions', v_stat -> 'interceptions',
    'rating',        v_stat -> 'rating',
    'rush_yards',    v_stat -> 'rush_yards',
    'rush_td',       v_stat -> 'rush_tds',
    'wins',          v_wins,
    'playoff_depth', v_depth
  );

  -- An award is earned when its score, nudged by up to noise_scale of the real
  -- winners' own spread either way, reaches its threshold. Only a season near the
  -- threshold is ever a coin flip. Super Bowl MVP needs the title.
  for v_award in select * from qb_season_builder_private.season_model_awards loop
    v_earned := qb_season_builder_private.metric_formula('award_' || v_award.award, v_metrics)
                  + (2 * qb_season_builder_private.unit_draw(p_seed, 'award:' || v_award.award) - 1)
                    * v_award.noise_scale * v_award.spread
                >= v_award.threshold
                and (v_award.award <> 'sb_mvp' or v_depth = 5);
    v_awards := v_awards || jsonb_build_object(v_award.award, v_earned);
  end loop;

  -- The score: where the season sits among the real seasons on each component,
  -- as the share of them it is strictly better than, mixed by the score weights.
  v_composite := jsonb_build_object(
    'stat_line',    qb_season_builder_private.metric_formula('stat_line', v_metrics),
    'team_success', qb_season_builder_private.metric_formula('team_success', v_metrics),
    'awards', (
      select coalesce(sum(f.weight), 0)
        from qb_season_builder_private.season_model_formulas f
       where f.formula = 'awards' and (v_awards ->> f.term)::boolean
    )
  );

  select jsonb_agg(
           jsonb_build_object(
             'component',  b.component,
             'weight',     b.weight,
             'percentile', b.percentile,
             'points',     b.points
           )
           order by array_position(array['stat_line', 'team_success', 'awards'], b.component)
         ),
         least(100, coalesce(sum(b.points), 0))
    into v_breakdown, v_score
    from (
      select w.term as component,
             w.weight,
             trim_scale(round(pct.share::numeric, 4)) as percentile,
             round((100 * w.weight * pct.share / sum(w.weight) over ())::numeric, 1) as points
        from qb_season_builder_private.season_model_formulas w
       cross join lateral (
         select count(*) filter (where d.value < (v_composite ->> w.term)::double precision)::double precision
                / count(*) as share
           from qb_season_builder_private.season_model_distributions d
          where d.component = w.term
       ) pct
       where w.formula = 'score'
    ) b;

  -- The real season nearest the build on the six values. Flavour only: it does not
  -- touch the score. Ties go to the earlier season, then the id, so it is stable.
  select jsonb_build_object(
           'franchise_code', r.franchise_code,
           'season',         r.season,
           'player_id',      r.player_id,
           'display_name',   r.display_name,
           'pass_yards',     r.pass_yards,
           'pass_tds',       r.pass_tds,
           'interceptions',  r.interceptions,
           'wins',           r.wins,
           'losses',         r.losses
         )
    into v_closest
    from qb_season_builder_private.season_model_real_seasons r
   order by (r.accuracy        - (p_values ->> 'accuracy')::int)  ^ 2
          + (r.arm_talent      - (p_values ->> 'arm_talent')::int) ^ 2
          + (r.mobility        - (p_values ->> 'mobility')::int)   ^ 2
          + (r.iq              - (p_values ->> 'iq')::int)         ^ 2
          + (r.build           - (p_values ->> 'build')::int)      ^ 2
          + (r.supporting_cast - (p_values ->> 'supporting_cast')::int) ^ 2,
            r.season, r.franchise_code, r.player_id
   limit 1;

  return jsonb_build_object(
    'stat_line', v_stat,
    'record',    jsonb_build_object('wins', v_wins, 'losses', 17 - v_wins),
    'playoffs',  jsonb_build_object(
      'depth',  v_depth,
      'result', (array['missed_playoffs', 'lost_wild_card', 'lost_divisional',
                       'lost_conference', 'lost_super_bowl', 'won_super_bowl'])[v_depth + 1]
    ),
    'awards',         v_awards,
    'score',          v_score,
    'breakdown',      v_breakdown,
    'closest_season', v_closest
  );
end;
$$;

-- A run's picks as a client sees them, oldest first: what was taken from whom and,
-- when p_reveal, what it was worth. The one definition of that shape, shared by the
-- board (state / pick / respin) and the saved result, so the recap in one can never
-- drift from the other.
create function qb_season_builder_private.picks_of(p_match_id uuid, p_reveal boolean)
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
             'value',          case when p_reveal then pv.value end
           )
           order by p.round_number
         ), '[]'::jsonb)
    from public.qb_season_builder_picks p
    join qb_season_builder_private.pick_values pv
      on pv.match_id = p.match_id and pv.slot = p.slot
   where p.match_id = p_match_id;
$$;

-- ---------------------------------------------------------------------- finish --

create function qb_season_builder_private.finish_run(p_match_id uuid, p_seed bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_match  public.matches;
  v_run    public.qb_season_builder_matches;
  v_user   uuid;
  v_values jsonb;
  v_picks  jsonb;
  v_season jsonb;
  v_result jsonb;
begin
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_match.status <> 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  select * into v_run from public.qb_season_builder_matches where match_id = p_match_id;
  if v_run.drafted_at is null then
    raise exception 'draft_incomplete' using errcode = 'P0001';
  end if;

  select rp.user_id into v_user from public.run_participants rp where rp.run_id = v_match.run_id;

  -- The values the run picked, and the per-pick recap: which real season each came
  -- from and what it was worth. These are the blended values, never a source rating.
  select jsonb_object_agg(pv.slot, pv.value) into v_values
    from qb_season_builder_private.pick_values pv where pv.match_id = p_match_id;

  v_picks := qb_season_builder_private.picks_of(p_match_id, true);

  v_season := qb_season_builder_private.generate_season(v_values, p_seed);

  v_result := jsonb_build_object('match_id', p_match_id, 'mode', v_run.mode)
              || v_season
              || jsonb_build_object('picks', v_picks);

  insert into qb_season_builder_private.season_results (match_id, seed, mode, score, result)
  values (p_match_id, p_seed, v_run.mode, (v_season ->> 'score')::numeric, v_result);

  perform private.finish_match(
    p_match_id, jsonb_build_object(v_user::text, (v_season ->> 'score')::numeric)
  );

  -- Only ever raised, never lowered, and only here: a run in play has no score.
  insert into public.qb_season_builder_player_stats as st (user_id, mode, best_score)
  values (v_user, v_run.mode, (v_season ->> 'score')::numeric)
  on conflict (user_id, mode) do update
    set best_score = excluded.best_score,
        updated_at = now()
    where excluded.best_score > st.best_score;

  return v_result;
end;
$$;

-- Generates the run's season from the six values it picked and saves it. The seed
-- is drawn here, when the season is generated, and is not an argument on purpose:
-- a client that could choose it could choose its season. Identity is auth.uid().
--
-- Errors are the contract with the client, matched by message:
--   not_authenticated, match_not_found, wrong_game, not_a_participant,
--   match_not_playing   as for pick (0121); a finished run is no longer playing
--   draft_incomplete    a slot is still open
create function qb_season_builder.finish(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform qb_season_builder_private.lock_playing_run(p_match_id, v_user);

  return qb_season_builder_private.finish_run(
    p_match_id,
    ('x' || substr(md5(gen_random_uuid()::text), 1, 15))::bit(60)::bigint
  );
end;
$$;

-- The saved result of a finished run: readable by anyone who has the run's id,
-- signed in or not, so a shared link works for a stranger and for a guest's run.
-- The id is a random uuid and is the whole capability. It is a projection, never a
-- table, so what it carries is decided here.
create function qb_season_builder.result(p_match_id uuid)
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

  return v_result;
end;
$$;

-- ------------------------------------------------------------- the reveal --

-- The board gains `shown`: once the run is finished, every spin the player was
-- shown with what each offered, values included, in either mode. In a hidden run
-- this is the reveal (every option, the ones passed on and a respun-away spin
-- too); in a visible one the player already saw it all. Null until then, so a
-- hidden run gives nothing away while it is in play.
alter type qb_season_builder.board add attribute shown jsonb;

-- 0121's projection with the finished run added: phase 'complete' once the season
-- is generated, and `shown`. A value is still shown or withheld in exactly one
-- place; this is that place.
create or replace function qb_season_builder_private.board_of(p_match_id uuid)
returns qb_season_builder.board
language plpgsql
-- Volatile on purpose, as in 0121.
security definer
set search_path = ''
as $$
declare
  v_run      public.qb_season_builder_matches;
  v_spin     public.qb_season_builder_spins;
  v_complete boolean;
  v_reveal   boolean;
  v_options  jsonb;
  v_picks    jsonb;
  v_shown    jsonb;
begin
  select * into v_run from public.qb_season_builder_matches where match_id = p_match_id;
  if not found then
    raise exception 'match_not_started' using errcode = 'P0002';
  end if;

  v_complete := exists (
    select 1 from public.matches m
     where m.id = p_match_id and m.status = 'complete'::public.match_status
  );
  v_reveal := v_run.mode = 'visible' or v_complete;

  v_picks := qb_season_builder_private.picks_of(p_match_id, v_reveal);

  if v_run.drafted_at is null then
    v_spin := qb_season_builder_private.current_spin_of(p_match_id, v_run.current_round);
    v_options := qb_season_builder_private.options_of(v_spin.franchise_code, v_spin.season, v_reveal);
  end if;

  if v_complete then
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'round',          s.round_number,
               'attempt',        s.attempt,
               'franchise_code', s.franchise_code,
               'season',         s.season,
               'options',        qb_season_builder_private.options_of(s.franchise_code, s.season, true)
             )
             order by s.round_number, s.attempt
           ), '[]'::jsonb)
      into v_shown
      from public.qb_season_builder_spins s
     where s.match_id = p_match_id;
  end if;

  return (
    v_run.match_id,
    v_run.mode,
    case when v_complete then 'complete'
         when v_run.drafted_at is null then 'picking'
         else 'ready_to_finish' end,
    v_run.round_count,
    v_run.current_round,
    v_run.respin_used,
    v_spin.franchise_code,
    v_spin.season,
    v_options,
    v_picks,
    v_shown
  )::qb_season_builder.board;
end;
$$;

-- ---------------------------------------------------------------- privileges --

revoke all on function qb_season_builder_private.unit_draw(bigint, text)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.residual_at(text, double precision)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.output_value(text, jsonb, bigint)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.metric_formula(text, jsonb)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.generate_season(jsonb, bigint)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.picks_of(uuid, boolean)
  from public, anon, authenticated;
revoke all on function qb_season_builder_private.finish_run(uuid, bigint)
  from public, anon, authenticated;

revoke all on function qb_season_builder.finish(uuid) from public, anon;
revoke all on function qb_season_builder.result(uuid) from public;

grant execute on function qb_season_builder.finish(uuid) to authenticated;
grant execute on function qb_season_builder.result(uuid) to anon, authenticated;
