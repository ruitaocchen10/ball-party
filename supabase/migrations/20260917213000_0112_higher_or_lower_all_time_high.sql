-- A solo run's best streak belongs to its match row; the personal record does
-- not. Keep the latter in one private, profile-keyed record.
create table public.higher_or_lower_player_stats (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  all_time_high integer not null default 0 check (all_time_high >= 0),
  updated_at timestamptz not null default now()
);

alter table public.higher_or_lower_player_stats enable row level security;

create policy higher_or_lower_player_stats_select_own
  on public.higher_or_lower_player_stats
  for select to authenticated
  using (auth.uid() = user_id and (auth.jwt() ->> 'is_anonymous')::boolean is not true);

-- Scoring is settled by the game functions, including solo's reveal path. A
-- trigger here keeps the durable record correct regardless of which path
-- revealed the answer, without widening client write access.
create function higher_or_lower_private.record_solo_all_time_high()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.best_streak > old.best_streak and exists (
    select 1 from public.higher_or_lower_matches
     where match_id = new.match_id and is_solo
  ) then
    insert into public.higher_or_lower_player_stats (user_id, all_time_high)
    values (new.user_id, new.best_streak)
    on conflict (user_id) do update
      set all_time_high = greatest(public.higher_or_lower_player_stats.all_time_high, excluded.all_time_high),
          updated_at = now();
  end if;
  return new;
end;
$$;

create trigger higher_or_lower_players_record_solo_all_time_high
  after update of best_streak on public.higher_or_lower_players
  for each row execute function higher_or_lower_private.record_solo_all_time_high();

revoke all on function higher_or_lower_private.record_solo_all_time_high() from public, anon, authenticated;
grant select on public.higher_or_lower_player_stats to authenticated;
