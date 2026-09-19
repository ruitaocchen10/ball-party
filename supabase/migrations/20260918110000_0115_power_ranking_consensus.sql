-- A safe aggregate read model for the Power Rankings right rail. It exposes
-- only team-level top-five frequency and average placement, never individual
-- ballots. The feed calls it under the same reveal conditions as
-- post_aggregates.
create function prompts.power_ranking_top_five(p_post_id uuid)
returns table (option_id uuid, top_five_count bigint, average_rank numeric)
language sql
security definer
set search_path = ''
stable
as $$
  with power_slot as (
    select s.id
    from public.prompt_posts p
    join public.prompt_slots s on s.post_id = p.id
    where p.id = p_post_id
      and p.template_kind = 'power_rankings'
      and s.shape = 'rank'
  ), ranked_choices as (
    select choice.option_id, choice.rank
    from public.prompt_responses r
    join power_slot s on s.id = r.slot_id
    cross join lateral unnest(r.chosen_option_ids) with ordinality as choice(option_id, rank)
    where choice.rank <= 5
  )
  select
    option_id,
    count(*) as top_five_count,
    round(avg(rank), 1) as average_rank
  from ranked_choices
  group by option_id
  order by top_five_count desc, average_rank asc, option_id
  limit 5;
$$;

revoke all on function prompts.power_ranking_top_five(uuid) from public;
grant execute on function prompts.power_ranking_top_five(uuid) to anon, authenticated;
