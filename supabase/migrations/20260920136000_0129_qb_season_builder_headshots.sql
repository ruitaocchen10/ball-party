-- QB Season Builder: publish the portrait for quarterbacks already on a spin.
--
-- The headshot table is private so a client cannot enumerate the pool, but a
-- quarterback's name is already part of a dealt spin. Its portrait is safe to
-- return alongside that name, in both visible and hidden rating modes.

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
                 'values', case when p_reveal then jsonb_build_object(
                   'accuracy',   q.accuracy,
                   'arm_talent', q.arm_talent,
                   'mobility',   q.mobility,
                   'iq',         q.iq,
                   'build',      q.build
                 ) end
               )
               order by q.player_id
             )
        from qb_season_builder_private.qb_seasons q
        left join private.av_player_headshots h on h.player_id = q.player_id
       where q.franchise_code = p_franchise_code and q.season = p_season
    ), '[]'::jsonb),
    'supporting_cast', jsonb_build_object(
      'value', (
        select case when p_reveal then t.supporting_cast end
          from qb_season_builder_private.team_seasons t
         where t.franchise_code = p_franchise_code and t.season = p_season
      )
    )
  );
$$;
