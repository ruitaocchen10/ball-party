-- QB Season Builder: a difficulty setting on the six values.
--
-- The formulas are fitted on real seasons, and a player who drafts well stacks values a real
-- quarterback rarely has all at once, so a strong build runs well ahead of the real league.
-- The model can now carry a curve, as two rows of season_model_formulas (`value_curve`:
-- `pivot` and `slope`), and output_value counts every value through it before the formula:
--
--   at or below `pivot`   the value counts in full
--   above it              pivot + (value - pivot) * slope
--
-- so with a pivot of 70 and a slope of 0.85 a 90 plays like an 87 and a 99 like a 94. It leaves
-- the floor alone: a weak build is no weaker, only a strong one comes down. Every output
-- (the line and the record alike) reads the same effective values, and the six values are
-- all treated the same. A model with no `value_curve` rows, or only one of them, counts every
-- value in full, so this migration changes nothing until a model that carries one is loaded (0147).

alter table qb_season_builder_private.season_model_formulas
  drop constraint season_model_formulas_formula_check;
alter table qb_season_builder_private.season_model_formulas
  add constraint season_model_formulas_formula_check check (formula in (
    'score', 'score_curve', 'wins_link', 'value_curve', 'stat_line', 'team_success', 'awards',
    'award_mvp', 'award_opoy', 'award_all_pro', 'award_pro_bowl', 'award_sb_mvp'
  ));

create or replace function qb_season_builder_private.output_value(p_output text, p_values jsonb, p_seed bigint)
returns double precision language plpgsql stable security definer set search_path = '' as $$
declare
  v_out qb_season_builder_private.season_model_outputs;
  v_z   double precision;
  v_u   double precision;
  v_rho double precision;
  v_line double precision;
  v_pivot double precision; v_slope double precision;
begin
  select * into v_out from qb_season_builder_private.season_model_outputs where output = p_output;

  -- The difficulty setting: a value counts in full up to the pivot and above it only `slope` of
  -- each point does. A model with no (or only half a) `value_curve` counts every value in full.
  select max(f.weight) filter (where f.term = 'pivot'), max(f.weight) filter (where f.term = 'slope')
    into v_pivot, v_slope
    from qb_season_builder_private.season_model_formulas f where f.formula = 'value_curve';

  select v_out.intercept + coalesce(sum(c.coefficient * case
           when v_pivot is not null and v_slope is not null and (p_values ->> c.slot)::double precision > v_pivot
             then v_pivot + ((p_values ->> c.slot)::double precision - v_pivot) * v_slope
           else (p_values ->> c.slot)::double precision end), 0)
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
