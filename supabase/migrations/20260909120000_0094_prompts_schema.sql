-- Ball-knowledge prompts: the tables behind components/social-prototype/,
-- which this migration turns from a localStorage mock into real schema.
-- Write API (create/submit/resolve) is 0095; this is tables, RLS and grants
-- only.
--
-- `prompts` / `prompts_private` follow the pair-of-schemas convention 0029
-- established for the auction (see docs/architecture/architecture.md and
-- supabase/README.md): `prompts` is the write API PostgREST exposes,
-- `prompts_private` is unreachable rules-engine/config. Unlike a game,
-- prompts has no lobby/match — a post is global, answerable by any
-- non-guest signed-in viewer, not scoped to a session.
--
-- Table shape mirrors components/social-prototype/types.ts almost exactly:
--   Post  -> prompt_posts
--   Slot  -> prompt_slots (+ prompt_slot_exclusions for excludesSlotIds)
--   Option -> prompt_slot_options
--   Comment -> prompt_comments
-- plus prompt_responses, which the prototype fakes as Post.viewerResponse.
--
-- THE ANSWER HIDING FOLLOWS THE AUCTION'S TWO-TABLE SPLIT (see 0010's
-- header). A slot's ground truth cannot be *written* to prompt_slots ahead
-- of resolution — that table is client-readable and in the Realtime
-- publication, so filling in a `correct_option_ids` column early would leak
-- it over the WebSocket before the UI ever asked. Ground truth lives in
-- private.prompt_slot_answers instead: no REST endpoint, no publication
-- membership, the thing an admin actually resolves from. Resolving a post
-- (0095) reads it, grades every response, and — same trick as
-- auction_lots.points — copies the answer onto prompt_slots.
-- correct_option_ids in the same transaction that flips the post to
-- 'resolved'. That copy is the reveal: the column was always there, but
-- carried no information until the moment it was meant to.

-- ------------------------------------------------------------------ schemas --

create schema if not exists prompts;
create schema if not exists prompts_private;

revoke all on schema prompts_private from public, anon, authenticated;

revoke all on schema prompts from public;
grant usage on schema prompts to anon, authenticated, service_role;

-- ------------------------------------------------------------------- posts --

create table public.prompt_posts (
  id                   uuid primary key default gen_random_uuid(),
  template_kind        text not null check (template_kind in ('game_pick', 'stat_leader', 'ranking', 'custom_multi')),
  template_name        text not null,
  author_id            uuid not null references public.profiles (id),
  caption              text not null,
  prompt_text          text not null,
  resolution_criteria  text not null,
  lock_at              timestamptz not null,
  status               text not null default 'open' check (status in ('open', 'locked', 'resolved', 'void')),
  void_reason          text,
  created_at           timestamptz not null default now(),
  resolved_at          timestamptz,
  -- Set when this post's ground truth can be read off a real-world event
  -- instead of an admin typing in an answer — see 0096's auto_resolve_tick,
  -- the only reader. 'winner' is the only rule today: a game_pick post
  -- whose one slot's options carry the two teams' nflverse team_code.
  -- Left null for stat_leader/ranking/custom_multi, which always wait for
  -- prompts.resolve_post — their answers aren't one mechanical lookup the
  -- way a final score is.
  resolution_source    jsonb,
  check ((status = 'void') = (void_reason is not null)),
  check ((status = 'resolved') = (resolved_at is not null)),
  check (resolution_source is null or (
    resolution_source ->> 'provider' = 'nflverse'
    and resolution_source ->> 'rule' = 'winner'
    and resolution_source ? 'game_id'
  ))
);

create index prompt_posts_status_lock_at on public.prompt_posts (status, lock_at);

-- ------------------------------------------------------------------ slots --

create table public.prompt_slots (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.prompt_posts (id) on delete cascade,
  label      text not null,
  shape      text not null check (shape in ('pick', 'pick_set', 'rank')),
  -- Only pick_set uses this — how many of the pool the viewer must choose.
  -- pick is always 1; rank is always "every option," so neither needs it.
  pick_count smallint check (pick_count > 0),
  points     smallint not null check (points > 0),
  sort_order smallint not null default 0,
  -- Null until resolve_post (0095) writes it. This is the reveal itself, the
  -- same trick auction_lots.points uses: the column sits on a client-
  -- readable, Realtime-published row from the start, but it carries no
  -- information until the same transaction that flips the post to
  -- 'resolved' fills it in — so there's nothing to leak early despite the
  -- column always having been there. private.prompt_slot_answers (below)
  -- remains the actual secret and the source resolve_post copies this from;
  -- this column is only ever a copy, never written to directly.
  correct_option_ids uuid[],
  check ((shape = 'pick_set') = (pick_count is not null))
);

create index prompt_slots_post_id on public.prompt_slots (post_id);

create table public.prompt_slot_options (
  id           uuid primary key default gen_random_uuid(),
  slot_id      uuid not null references public.prompt_slots (id) on delete cascade,
  label        text not null,
  sublabel     text,
  team_code    text,
  headshot_url text,
  sort_order   smallint not null default 0
);

create index prompt_slot_options_slot_id on public.prompt_slot_options (slot_id);

-- excludesSlotIds from types.ts, as a join table rather than an array column
-- so the submit-response RPC in 0095 can join against it directly instead of
-- unpacking an array server-side.
create table public.prompt_slot_exclusions (
  slot_id          uuid not null references public.prompt_slots (id) on delete cascade,
  excluded_slot_id uuid not null references public.prompt_slots (id) on delete cascade,
  primary key (slot_id, excluded_slot_id),
  check (slot_id <> excluded_slot_id)
);

-- ------------------------------------------------------------ hidden answers --

create table private.prompt_slot_answers (
  slot_id            uuid primary key references public.prompt_slots (id) on delete cascade,
  -- Order matters for `rank`; ignored (but still just the one true set) for
  -- `pick` and `pick_set`.
  correct_option_ids uuid[] not null check (array_length(correct_option_ids, 1) > 0)
);

revoke all on table private.prompt_slot_answers from public, anon, authenticated;
alter table private.prompt_slot_answers enable row level security;
-- No policies: unreachable by anything but a security definer function, same
-- as private.auction_answers (0010).

-- -------------------------------------------------------------- responses --

create table public.prompt_responses (
  id                uuid primary key default gen_random_uuid(),
  post_id           uuid not null references public.prompt_posts (id) on delete cascade,
  slot_id           uuid not null references public.prompt_slots (id) on delete cascade,
  profile_id        uuid not null references public.profiles (id),
  chosen_option_ids uuid[] not null check (array_length(chosen_option_ids, 1) > 0),
  -- Null until the post resolves. Scoped to this feature only — no
  -- cross-feature points ledger, matching how auction/sabotage-draft each
  -- keep their own standings rather than a shared score.
  points_earned     smallint,
  created_at        timestamptz not null default now(),
  unique (slot_id, profile_id)
);

create index prompt_responses_post_id on public.prompt_responses (post_id);
create index prompt_responses_profile_id on public.prompt_responses (profile_id);

-- -------------------------------------------------------------- comments --

create table public.prompt_comments (
  id               uuid primary key default gen_random_uuid(),
  post_id          uuid not null references public.prompt_posts (id) on delete cascade,
  author_id        uuid not null references public.profiles (id),
  body             text not null check (char_length(trim(body)) between 1 and 280),
  -- True for a take attached at the moment the author locked in their pick,
  -- false for an ordinary thread reply. Not a response_id FK: custom_multi
  -- posts write several prompt_responses rows (one per slot) for a single
  -- "Lock in," so there is no one slot response a submission-time comment
  -- unambiguously belongs to. This flag says "posted alongside a pick on
  -- this post," without pretending it anchors to a specific slot.
  posted_with_pick boolean not null default false,
  created_at       timestamptz not null default now()
);

create index prompt_comments_post_id on public.prompt_comments (post_id);

-- ----------------------------------------------------------------- admin --

-- Exactly one admin, matched by email — the DB-side twin of
-- lib/auth/viewer.ts's isAdminViewer. That check gates the /admin/* page
-- render; this is the same check enforced again at the RPC layer in 0095,
-- because a page guard alone doesn't stop a direct API call. A table rather
-- than a literal in this function so the admin's email isn't a value this
-- committed migration has to carry. Set it once after migrating:
--   insert into prompts_private.admin_config (email) values ('you@example.com');
create table prompts_private.admin_config (
  email text primary key
);

revoke all on table prompts_private.admin_config from public, anon, authenticated;
alter table prompts_private.admin_config enable row level security;

create function prompts_private.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from prompts_private.admin_config c
    where lower(c.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function prompts_private.is_admin() from public, anon;
grant execute on function prompts_private.is_admin() to authenticated;

-- ------------------------------------------------------------------- RLS --

alter table public.prompt_posts           enable row level security;
alter table public.prompt_slots           enable row level security;
alter table public.prompt_slot_options    enable row level security;
alter table public.prompt_slot_exclusions enable row level security;
alter table public.prompt_responses       enable row level security;
alter table public.prompt_comments        enable row level security;

-- The feed is global, not session-scoped, so read access is just "signed in"
-- rather than any membership check — no private.is_*_member equivalent
-- needed here.
create policy prompt_posts_select_authenticated on public.prompt_posts
  for select to authenticated using (true);

create policy prompt_slots_select_authenticated on public.prompt_slots
  for select to authenticated using (true);

create policy prompt_slot_options_select_authenticated on public.prompt_slot_options
  for select to authenticated using (true);

create policy prompt_slot_exclusions_select_authenticated on public.prompt_slot_exclusions
  for select to authenticated using (true);

-- Own picks only. Nobody gets to read another profile's response row
-- directly — the aggregate percentages in 0095's prompts.post_aggregates
-- are the only view onto what other people picked, and that's a rounded
-- percentage, never a row.
create policy prompt_responses_select_own on public.prompt_responses
  for select to authenticated using (profile_id = auth.uid());

-- Comments are public discussion, same as the prototype's Post.comments.
create policy prompt_comments_select_authenticated on public.prompt_comments
  for select to authenticated using (true);

-- No INSERT/UPDATE/DELETE policies anywhere, consistent with every other
-- game in this codebase. Every write goes through a security definer
-- function (0095), which bypasses both the grant and the policy.

grant select on public.prompt_posts           to authenticated;
grant select on public.prompt_slots            to authenticated;
grant select on public.prompt_slot_options     to authenticated;
grant select on public.prompt_slot_exclusions  to authenticated;
grant select on public.prompt_responses        to authenticated;
grant select on public.prompt_comments         to authenticated;

-- ------------------------------------------------------------- realtime --

alter publication supabase_realtime add table public.prompt_posts;
alter publication supabase_realtime add table public.prompt_slots;
alter publication supabase_realtime add table public.prompt_slot_options;
alter publication supabase_realtime add table public.prompt_slot_exclusions;
alter publication supabase_realtime add table public.prompt_comments;
-- prompt_responses deliberately NOT published: Realtime replicates whole
-- rows regardless of a subscriber's own RLS grant, and this table's whole
-- reason for row-level security is that nobody should see another
-- profile's pick. The feed gets its "what did other people pick" view from
-- prompts.post_aggregates (0095) instead, which returns percentages, not
-- rows.
