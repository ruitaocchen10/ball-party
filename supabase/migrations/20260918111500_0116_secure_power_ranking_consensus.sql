-- Do not let an open Power Rankings prompt reveal the group board to someone
-- who has not submitted a ballot. This mirrors the feed's reveal rule at the
-- database boundary, which is required because the RPC is callable directly.
create or replace function prompts.power_ranking_top_five(p_post_id uuid)
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
      and (
        p.status <> 'open'
        or exists (
          select 1
          from public.prompt_responses mine
          where mine.post_id = p.id and mine.profile_id = auth.uid()
        )
      )
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
