-- QB Season Builder: a soft ceiling on the finished score.
--
-- The score ranks a season against the real ones, so a drafted build that is better than
-- nearly every real season on the stat line has no room left, and the top of the score is
-- decided by whether the awards and the playoff bracket come off. The model can now carry a
-- curve, as two rows of season_model_formulas (`score_curve`: `start` and `exponent`), and
-- generate_season applies it to the mixed score:
--
--   at or below `start`   the score is unchanged
--   above it              start + (100 - start) * ((score - start) / (100 - start)) ^ exponent
--
-- 0 and 100 stay where they are, and a better mixed score is never a worse curved one. A
-- model with no `score_curve` rows scores exactly as it did, so this migration changes
-- nothing until a model that has them is loaded (0142).
--
-- The breakdown still adds up to the score: each component's points are scaled by the same
-- factor (curved score / mixed score) before they are rounded, and the score is their sum.

alter table qb_season_builder_private.season_model_formulas
  drop constraint season_model_formulas_formula_check;
alter table qb_season_builder_private.season_model_formulas
  add constraint season_model_formulas_formula_check check (formula in (
    'score', 'score_curve', 'stat_line', 'team_success', 'awards',
    'award_mvp', 'award_opoy', 'award_all_pro', 'award_pro_bowl', 'award_sb_mvp'
  ));

create or replace function qb_season_builder_private.generate_season(p_values jsonb, p_seed bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_out jsonb; v_attempts double precision; v_comp_pct double precision;
  v_ypa double precision; v_td_rate double precision; v_int_rate double precision;
  v_stat jsonb; v_wins int; v_depth int := 0;
  v_rung qb_season_builder_private.season_model_playoff_ladder;
  v_award qb_season_builder_private.season_model_awards;
  v_awards jsonb := '{}'::jsonb; v_metrics jsonb; v_earned boolean;
  v_composite jsonb; v_breakdown jsonb; v_score numeric;
begin
  select jsonb_object_agg(o.output, qb_season_builder_private.output_value(o.output, p_values, p_seed))
    into v_out from qb_season_builder_private.season_model_outputs o;
  v_attempts := (v_out ->> 'attempts')::double precision;
  v_comp_pct := (v_out ->> 'comp_pct')::double precision;
  v_ypa := (v_out ->> 'ypa')::double precision;
  v_td_rate := (v_out ->> 'td_rate')::double precision;
  v_int_rate := (v_out ->> 'int_rate')::double precision;
  v_stat := jsonb_build_object(
    'attempts', round(v_attempts::numeric)::int,
    'completions', round((v_attempts * v_comp_pct)::numeric)::int,
    'pass_yards', round((v_attempts * v_ypa)::numeric)::int,
    'pass_tds', round((v_attempts * v_td_rate)::numeric)::int,
    'interceptions', round((v_attempts * v_int_rate)::numeric)::int,
    'rating', round((least(2.375, greatest(0, (v_comp_pct - 0.3) * 5))
      + least(2.375, greatest(0, (v_ypa - 3) * 0.25))
      + least(2.375, greatest(0, v_td_rate * 20))
      + least(2.375, greatest(0, 2.375 - v_int_rate * 25)))::numeric / 6 * 100, 1),
    'rush_yards', round((v_out ->> 'rush_yards')::numeric)::int,
    'rush_tds', round((v_out ->> 'rush_td')::numeric)::int);
  v_wins := round((v_out ->> 'wins')::numeric)::int;
  -- A rung may carry a guarantee (see the header of 0139): at or above always_from wins it
  -- is cleared and at or below never_to it is missed, whatever the draw says. Every draw is
  -- a hash of the seed and its own label, so skipping one changes none of the others.
  for v_rung in select * from qb_season_builder_private.season_model_playoff_ladder order by rung loop
    exit when case
      when v_rung.always_from is not null and v_wins >= v_rung.always_from then false
      when v_rung.never_to is not null and v_wins <= v_rung.never_to then true
      else qb_season_builder_private.unit_draw(p_seed, 'ladder:' || v_rung.step)
             >= 1 / (1 + exp(-(v_rung.intercept + v_rung.slope * v_wins)))
    end;
    v_depth := v_depth + 1;
  end loop;
  v_metrics := jsonb_build_object(
    'pass_yards', v_stat -> 'pass_yards', 'pass_td', v_stat -> 'pass_tds',
    'interceptions', v_stat -> 'interceptions', 'rating', v_stat -> 'rating',
    'rush_yards', v_stat -> 'rush_yards', 'rush_td', v_stat -> 'rush_tds',
    'wins', v_wins, 'playoff_depth', v_depth);
  for v_award in select * from qb_season_builder_private.season_model_awards
    order by array_position(array['pro_bowl', 'all_pro', 'opoy', 'mvp', 'sb_mvp'], award)
  loop
    v_earned := qb_season_builder_private.metric_formula('award_' || v_award.award, v_metrics)
      + (2 * qb_season_builder_private.unit_draw(p_seed, 'award:' || v_award.award) - 1)
        * v_award.noise_scale * v_award.spread >= v_award.threshold
      and (v_award.award <> 'sb_mvp' or v_depth = 5)
      and (v_award.requires = '' or coalesce((v_awards ->> v_award.requires)::boolean, false));
    v_awards := v_awards || jsonb_build_object(v_award.award, v_earned);
  end loop;
  v_composite := jsonb_build_object(
    'stat_line', qb_season_builder_private.metric_formula('stat_line', v_metrics),
    'team_success', qb_season_builder_private.metric_formula('team_success', v_metrics),
    'awards', (select coalesce(sum(f.weight), 0) from qb_season_builder_private.season_model_formulas f
               where f.formula = 'awards' and (v_awards ->> f.term)::boolean));

  -- Each component's points from where the season ranks on it; then the soft ceiling, as one
  -- factor on all of them so the breakdown still adds up to the score.
  with parts as (
    select w.term as component, w.weight, trim_scale(round(pct.share::numeric, 4)) as percentile,
           100 * w.weight * pct.share / sum(w.weight) over () as raw_points
      from qb_season_builder_private.season_model_formulas w
      cross join lateral (
        select count(*) filter (where d.value < (v_composite ->> w.term)::double precision)::double precision
          / count(*) as share from qb_season_builder_private.season_model_distributions d
         where d.component = w.term
      ) pct where w.formula = 'score'
  ), mixed as (
    select coalesce(sum(raw_points), 0) as raw from parts
  ), curve as (
    select max(f.weight) filter (where f.term = 'start') as start_at,
           max(f.weight) filter (where f.term = 'exponent') as exponent
      from qb_season_builder_private.season_model_formulas f where f.formula = 'score_curve'
  )
  select jsonb_agg(jsonb_build_object('component', b.component, 'weight', b.weight,
             'percentile', b.percentile, 'points', b.points)
             order by array_position(array['stat_line', 'team_success', 'awards'], b.component)),
         least(100, coalesce(sum(b.points), 0)) into v_breakdown, v_score
    from (
      select p.component, p.weight, p.percentile,
             round((p.raw_points * case
               when c.start_at is null or c.exponent is null or m.raw <= c.start_at or m.raw <= 0 then 1
               else (c.start_at + (100 - c.start_at) * power((m.raw - c.start_at) / (100 - c.start_at), c.exponent))
                    / m.raw
             end)::numeric, 1) as points
        from parts p cross join mixed m cross join curve c
    ) b;

  return jsonb_build_object(
    'stat_line', v_stat, 'record', jsonb_build_object('wins', v_wins, 'losses', 17 - v_wins),
    'playoffs', jsonb_build_object('depth', v_depth, 'result',
      (array['missed_playoffs', 'lost_wild_card', 'lost_divisional', 'lost_conference',
             'lost_super_bowl', 'won_super_bowl'])[v_depth + 1]),
    'awards', v_awards, 'score', v_score, 'breakdown', v_breakdown);
end;
$$;
