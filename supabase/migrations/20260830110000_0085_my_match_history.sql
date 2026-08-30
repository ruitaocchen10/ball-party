-- A player's own profile needs their full record, including games from lobbies
-- they have since left. Core-table RLS intentionally exposes those rows only
-- while a lobby membership is active, so this narrowly-scoped RPC is the
-- profile-only escape hatch rather than a broadening of those policies.
create function public.my_match_history()
returns table (
  match_id uuid,
  game text,
  ended_at timestamptz,
  placement smallint,
  raw_score numeric,
  mode public.run_mode
)
language sql
stable
security definer
set search_path = ''
as $$
  select mp.match_id, m.game, m.ended_at, mp.placement, mp.raw_score, r.mode
    from public.match_players mp
    join public.matches m on m.id = mp.match_id
    join public.runs r on r.id = m.run_id
   where mp.user_id = auth.uid()
     and m.status = 'complete'::public.match_status
     and m.ended_at is not null
   order by m.ended_at desc;
$$;

revoke all on function public.my_match_history() from public, anon;
grant execute on function public.my_match_history() to authenticated;
