-- QB Season Builder: awards that depend on one another.
--
-- 0127 judged the five awards independently, each on its own noisy score. Real awards
-- do not behave that way: of 2006-2025's 18 quarterback MVPs, 17 were first-team
-- All-Pro and all 18 went to the Pro Bowl; every one of the 20 All-Pros did too. Judged
-- independently, 46% of generated MVPs were not All-Pro. An award can now name the
-- award it requires (`requires`), and generate_season judges the awards in that
-- order. The fit fills the column; the rules in force are in
-- scripts/qb_season_model/config.py (AWARD_REQUIRES).
--
-- Replaces generate_season whole (create or replace), changing only the award loop.

alter table qb_season_builder_private.season_model_awards
  add column requires text not null default ''
    check (requires in ('', 'mvp', 'opoy', 'all_pro', 'pro_bowl', 'sb_mvp'));

create or replace function qb_season_builder_private.generate_season(p_values jsonb, p_seed bigint)
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
  -- threshold is ever a coin flip. Super Bowl MVP needs the title. An award may also
  -- require another (an MVP is an All-Pro, and every All-Pro went to the Pro Bowl),
  -- so they are judged in that order, the required one first, and each draw is still
  -- its own: a season is never handed an award whose parent it missed.
  for v_award in
    select * from qb_season_builder_private.season_model_awards
     order by array_position(array['pro_bowl', 'all_pro', 'opoy', 'mvp', 'sb_mvp'], award)
  loop
    v_earned := qb_season_builder_private.metric_formula('award_' || v_award.award, v_metrics)
                  + (2 * qb_season_builder_private.unit_draw(p_seed, 'award:' || v_award.award) - 1)
                    * v_award.noise_scale * v_award.spread
                >= v_award.threshold
                and (v_award.award <> 'sb_mvp' or v_depth = 5)
                and (v_award.requires = '' or coalesce((v_awards ->> v_award.requires)::boolean, false));
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
