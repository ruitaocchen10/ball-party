-- The prompt composer needs card-safe player identity data, not the private
-- pool's scoring fields. Read the newest loaded season so the available
-- candidates advance whenever the normal player-pool refresh lands.
create function prompts.player_options()
returns table (
  player_id text,
  display_name text,
  "position" text,
  team text,
  headshot_url text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not prompts_private.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  return query
  select season.player_id, season.display_name, season.position, season.team, portrait.headshot_url
  from private.player_seasons season
  left join private.player_headshots portrait on portrait.player_id = season.player_id
  where season.season = (select max(latest.season) from private.player_seasons latest)
  order by season.position, season.display_name;
end;
$$;

revoke all on function prompts.player_options() from public, anon;
grant execute on function prompts.player_options() to authenticated;
