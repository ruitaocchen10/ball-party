-- A picked quarterback remains visible in the player's build, so publish the
-- portrait already shown on their dealt spin alongside that pick. The headshot
-- table itself remains private; this projection is scoped to a run the caller
-- may already read.
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
             'value',          case when p_reveal then pv.value end
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
