create type higher_or_lower.era as (season_min smallint, season_max smallint);
create function higher_or_lower.season_bounds() returns higher_or_lower.era
language sql stable security definer set search_path = ''
as $$ select (b.season_min, b.season_max)::higher_or_lower.era from higher_or_lower_private.season_bounds() b $$;
revoke all on function higher_or_lower.season_bounds() from public, anon;
grant execute on function higher_or_lower.season_bounds() to authenticated;
