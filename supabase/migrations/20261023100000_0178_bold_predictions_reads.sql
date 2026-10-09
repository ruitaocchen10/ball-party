-- Two read helpers the Bold Predictions UI needs on top of 0171/0172.
--
-- prompts.players_by_ids: a revealed prediction tagged to a player stores only
-- the player's id (0171), but the reveal has to draw their name, team and
-- headshot. prompts_private.nfl_players is not readable by clients (0172), so
-- this is the lookup. Identity fields only, same as search_players — and
-- open to anon, because the reveal itself is public like the Huddle (0112).
--
-- prompts.bold_prediction_counts: the Home card shows how many predictions a
-- post has, but bold_predictions is own-rows-only until lock. A count is not
-- the text, so it is safe to show before lock; it is a security-definer read
-- for the same reason prompts.post_aggregates is.

create function prompts.players_by_ids(p_ids text[])
returns table (
  player_id text,
  display_name text,
  "position" text,
  team text,
  headshot_url text,
  status text
)
language sql
security definer
set search_path = ''
stable
as $$
  select p.player_id, p.display_name, p.position, p.team, p.headshot_url, p.status
    from prompts_private.nfl_players p
   where p.player_id = any (p_ids[1:200]);
$$;

create function prompts.bold_prediction_counts(p_post_ids uuid[])
returns table (post_id uuid, prediction_count bigint, author_count bigint)
language sql
security definer
set search_path = ''
stable
as $$
  select bp.post_id, count(*), count(distinct bp.author_id)
    from public.bold_predictions bp
   where bp.post_id = any (p_post_ids)
   group by bp.post_id;
$$;

revoke all on function prompts.players_by_ids(text[])           from public;
revoke all on function prompts.bold_prediction_counts(uuid[])   from public;
grant execute on function prompts.players_by_ids(text[])         to anon, authenticated;
grant execute on function prompts.bold_prediction_counts(uuid[]) to anon, authenticated;
