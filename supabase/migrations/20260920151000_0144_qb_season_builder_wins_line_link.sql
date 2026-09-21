-- QB Season Builder: a link between the quarterback's line and his team's record.
--
-- Every output's noise is drawn from its own hash of the seed, so a season's record has been
-- independent of how the quarterback happened to play: a build whose passing came out average
-- could go 12-5 as easily as one whose passing came out great. The real seasons link the two
-- a little (the wins residual correlates 0.06 to 0.13 with the line's residuals), and the game
-- can now link them as much as the model says. The model carries it as one row of
-- season_model_formulas (`wins_link`: `rho`, a correlation from 0 up to but not including 1),
-- and output_value applies it to the `wins` draw only:
--
--   n_line  = (N(ypa) + N(td_rate) - N(int_rate) + N(comp_pct)) / 2
--   n_wins' = rho * n_line + sqrt(1 - rho^2) * N(wins)
--   wins    is drawn at u = Phi(n_wins')
--
-- where N is the normal score (the inverse normal CDF) of that output's own draw, so a better
-- rate line (more yards and touchdowns per pass, fewer interceptions, more completions) pulls
-- the record's draw up. The four are independent uniform draws, so n_line is a standard normal
-- and so is n_wins'; the record's own spread, and a build's average record, are exactly what
-- they were, and only which record goes with which line changes. A model with no `wins_link`
-- row, or with rho = 0, draws exactly as before, so this migration changes nothing until a
-- model that carries one is loaded (0145).
--
-- norm_cdf is Abramowitz & Stegun 26.2.17 (absolute error under 1e-7) and norm_inv is
-- Acklam's rational approximation (relative error about 1e-9); beyond 8 standard deviations
-- norm_cdf is exactly 0 or 1. Both are pure, so a season is still a deterministic function of the
-- values and the seed.

alter table qb_season_builder_private.season_model_formulas
  drop constraint season_model_formulas_formula_check;
alter table qb_season_builder_private.season_model_formulas
  add constraint season_model_formulas_formula_check check (formula in (
    'score', 'score_curve', 'wins_link', 'stat_line', 'team_success', 'awards',
    'award_mvp', 'award_opoy', 'award_all_pro', 'award_pro_bowl', 'award_sb_mvp'
  ));

create or replace function qb_season_builder_private.norm_cdf(p_x double precision)
returns double precision language sql immutable set search_path = '' as $$
  select case when p_x > 8 then 1 when p_x < -8 then 0
              else least(1, greatest(0, case when p_x >= 0 then 1 - t.tail else t.tail end)) end
    from (
      select exp(-0.5 * p_x * p_x) / sqrt(2 * pi())
             * (w.k * (0.319381530 + w.k * (-0.356563782 + w.k * (1.781477937
                + w.k * (-1.821255978 + w.k * 1.330274429))))) as tail
        from (select 1 / (1 + 0.2316419 * abs(p_x)) as k) w
    ) t;
$$;

create or replace function qb_season_builder_private.norm_inv(p_p double precision)
returns double precision language plpgsql immutable set search_path = '' as $$
declare
  v_p double precision := least(greatest(p_p, 1e-10), 1 - 1e-10);
  v_q double precision; v_r double precision;
begin
  if v_p < 0.02425 then
    v_q := sqrt(-2 * ln(v_p));
    return (((((-7.784894002430293e-03 * v_q - 3.223964580411365e-01) * v_q - 2.400758277161838e+00) * v_q
              - 2.549732539343734e+00) * v_q + 4.374664141464968e+00) * v_q + 2.938163982698783e+00)
         / ((((7.784695709041462e-03 * v_q + 3.224671290700398e-01) * v_q + 2.445134137142996e+00) * v_q
              + 3.754408661907416e+00) * v_q + 1);
  elsif v_p > 1 - 0.02425 then
    v_q := sqrt(-2 * ln(1 - v_p));
    return -(((((-7.784894002430293e-03 * v_q - 3.223964580411365e-01) * v_q - 2.400758277161838e+00) * v_q
               - 2.549732539343734e+00) * v_q + 4.374664141464968e+00) * v_q + 2.938163982698783e+00)
          / ((((7.784695709041462e-03 * v_q + 3.224671290700398e-01) * v_q + 2.445134137142996e+00) * v_q
               + 3.754408661907416e+00) * v_q + 1);
  end if;
  v_q := v_p - 0.5;
  v_r := v_q * v_q;
  return (((((-3.969683028665376e+01 * v_r + 2.209460984245205e+02) * v_r - 2.759285104469687e+02) * v_r
            + 1.383577518672690e+02) * v_r - 3.066479806614716e+01) * v_r + 2.506628277459239e+00) * v_q
       / (((((-5.447609879822406e+01 * v_r + 1.615858368580409e+02) * v_r - 1.556989798598866e+02) * v_r
            + 6.680131188771972e+01) * v_r - 1.328068155288572e+01) * v_r + 1);
end;
$$;

create or replace function qb_season_builder_private.output_value(p_output text, p_values jsonb, p_seed bigint)
returns double precision language plpgsql stable security definer set search_path = '' as $$
declare
  v_out qb_season_builder_private.season_model_outputs;
  v_z   double precision;
  v_u   double precision;
  v_rho double precision;
  v_line double precision;
begin
  select * into v_out from qb_season_builder_private.season_model_outputs where output = p_output;

  select v_out.intercept + coalesce(sum(c.coefficient * (p_values ->> c.slot)::double precision), 0)
    into v_z
    from qb_season_builder_private.season_model_coefficients c
   where c.output = p_output;

  v_u := qb_season_builder_private.unit_draw(p_seed, 'noise:' || p_output);

  -- The record's draw follows the quarterback's line by `rho`, in normal scores (see above).
  if p_output = 'wins' then
    select f.weight into v_rho from qb_season_builder_private.season_model_formulas f
     where f.formula = 'wins_link' and f.term = 'rho';
    if coalesce(v_rho, 0) > 0 then
      v_line := (qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(p_seed, 'noise:ypa'))
               + qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(p_seed, 'noise:td_rate'))
               - qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(p_seed, 'noise:int_rate'))
               + qb_season_builder_private.norm_inv(qb_season_builder_private.unit_draw(p_seed, 'noise:comp_pct'))) / 2;
      v_u := qb_season_builder_private.norm_cdf(
        v_rho * v_line + sqrt(1 - v_rho * v_rho) * qb_season_builder_private.norm_inv(v_u));
    end if;
  end if;

  v_z := v_z + v_out.noise_scale * qb_season_builder_private.residual_at(p_output, v_u);

  return case v_out.link
    when 'identity' then least(v_out.high, greatest(v_out.low, v_z))
    when 'log'      then least(v_out.high, exp(v_z))
    when 'logit'    then v_out.low + (v_out.high - v_out.low) / (1 + exp(-v_z))
  end;
end;
$$;

-- The private schema is unreachable by client roles (0120); a new function still starts with
-- the default PUBLIC execute grant, so it is revoked here as the second lock.
revoke all on function qb_season_builder_private.norm_cdf(double precision) from public, anon, authenticated;
revoke all on function qb_season_builder_private.norm_inv(double precision) from public, anon, authenticated;
