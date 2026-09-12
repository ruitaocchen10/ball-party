-- Product feedback is write-only to players. It is intentionally not a
-- discussion surface: the team can triage it, while one player's report can
-- never be read by another through PostgREST.

create table public.feedback (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('bug', 'feature')),
  message     text not null check (char_length(message) between 3 and 2000),
  route       text not null check (char_length(route) between 1 and 2048),
  reporter_id uuid references public.profiles (id) on delete set null,
  status      text not null default 'new' check (status in ('new', 'reviewing', 'planned', 'resolved', 'closed')),
  created_at  timestamptz not null default now()
);

create index feedback_status_created_at on public.feedback (status, created_at desc);

alter table public.feedback enable row level security;

-- The server action supplies auth.uid() as reporter_id. Anonymous feedback is
-- allowed too, but neither anonymous nor signed-in callers can select, edit,
-- or delete records.
create policy feedback_insert on public.feedback
  for insert to anon, authenticated
  with check (reporter_id is null or reporter_id = auth.uid());

grant insert on public.feedback to anon, authenticated;
