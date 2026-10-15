-- Ranking lists (1/3): the schema. See docs/architecture/ranking-lists.md.
--
-- A player keeps one living ranking per list kind (team power rankings, top
-- QBs, ...). Each save is an immutable, numbered version, so a list's history
-- is an honest record. 0211 adds the write and read API and the friends-only
-- update card; 0212 wires prompt answers into lists and backfills the
-- existing Power Rankings responses.
--
-- Items are keyed by team_code / player_id, never by prompt option id: option
-- ids are per post, and a list outlives any prompt.

-- ------------------------------------------------------------------- kinds --

-- Seeded config. Adding a list kind is an insert.
create table public.ranking_list_kinds (
  id              text primary key,
  label           text not null,
  item_kind       text not null check (item_kind in ('team', 'player')),
  -- Player kinds only: the nfl_players position the list draws from.
  player_position text,
  -- Allowed list lengths.
  sizes           smallint[] not null check (array_length(sizes, 1) > 0),
  check ((item_kind = 'player') = (player_position is not null))
);

insert into public.ranking_list_kinds (id, label, item_kind, player_position, sizes) values
  ('power_rankings', 'Power Rankings',   'team',   null, '{5,10,32}'),
  ('qb',             'Quarterbacks',     'player', 'QB', '{10}'),
  ('rb',             'Running backs',    'player', 'RB', '{10}'),
  ('wr',             'Wide receivers',   'player', 'WR', '{10}'),
  ('te',             'Tight ends',       'player', 'TE', '{10}');

alter table public.ranking_list_kinds enable row level security;
create policy ranking_list_kinds_select on public.ranking_list_kinds
  for select to anon, authenticated using (true);
revoke all on table public.ranking_list_kinds from public, anon, authenticated;
grant select on table public.ranking_list_kinds to anon, authenticated;

-- ------------------------------------------------------------------- lists --

create table public.ranking_lists (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles (id) on delete cascade,
  kind               text not null references public.ranking_list_kinds (id),
  -- The latest version. Maintained by the write functions.
  current_version_id uuid,
  created_at         timestamptz not null default now(),
  unique (profile_id, kind)
);

-- ---------------------------------------------------------------- versions --

create table public.ranking_list_versions (
  id             uuid primary key default gen_random_uuid(),
  list_id        uuid not null references public.ranking_lists (id) on delete cascade,
  version_no     integer not null check (version_no > 0),
  -- edit: saved from the editor. prompt: the player's answer to a ranking
  -- prompt (post_id), which also stays in prompt_responses.
  source         text not null check (source in ('edit', 'prompt')),
  post_id        uuid references public.prompt_posts (id) on delete set null,
  -- The friends-only update card, once the player publishes an edit.
  update_post_id uuid references public.prompt_posts (id) on delete set null,
  note           text check (char_length(note) between 1 and 280),
  created_at     timestamptz not null default now(),
  -- Moves only when a version is replaced: a save inside the typo-grace
  -- window, or a resubmit of a prompt that is still open.
  updated_at     timestamptz not null default now(),
  unique (list_id, version_no),
  -- One version per prompt per list (a resubmit overwrites it).
  unique (list_id, post_id)
);

create unique index ranking_list_versions_update_post
  on public.ranking_list_versions (update_post_id) where update_post_id is not null;

alter table public.ranking_lists
  add constraint ranking_lists_current_version_fk
  foreign key (current_version_id) references public.ranking_list_versions (id) on delete set null;

-- ------------------------------------------------------------------- items --

create table public.ranking_list_items (
  version_id uuid not null references public.ranking_list_versions (id) on delete cascade,
  place      smallint not null check (place > 0),
  team_code  text,
  player_id  text,
  primary key (version_id, place),
  check ((team_code is null) <> (player_id is null))
);

create unique index ranking_list_items_team
  on public.ranking_list_items (version_id, team_code) where team_code is not null;
create unique index ranking_list_items_player
  on public.ranking_list_items (version_id, player_id) where player_id is not null;

-- Owner-only reads and no write policies. Everyone else reads through the
-- RPCs in 0211, so privacy (private profiles, blocks) lives in one place.
alter table public.ranking_lists enable row level security;
alter table public.ranking_list_versions enable row level security;
alter table public.ranking_list_items enable row level security;

create policy ranking_lists_select_own on public.ranking_lists
  for select to authenticated using (profile_id = auth.uid());
create policy ranking_list_versions_select_own on public.ranking_list_versions
  for select to authenticated using (
    exists (select 1 from public.ranking_lists l where l.id = list_id and l.profile_id = auth.uid())
  );
create policy ranking_list_items_select_own on public.ranking_list_items
  for select to authenticated using (
    exists (
      select 1 from public.ranking_list_versions v
        join public.ranking_lists l on l.id = v.list_id
       where v.id = version_id and l.profile_id = auth.uid()
    )
  );

revoke all on table public.ranking_lists, public.ranking_list_versions, public.ranking_list_items
  from public, anon, authenticated;
grant select on table public.ranking_lists, public.ranking_list_versions, public.ranking_list_items
  to authenticated;

-- ------------------------------------------------- prompts bound to a list --

-- Which list kind a prompt feeds. Null for every prompt that is not a ranking
-- prompt. A Power Rankings post feeds 'power_rankings'; a later position-list
-- prompt names its own kind.
alter table public.prompt_posts
  add column ranking_kind text references public.ranking_list_kinds (id);

update public.prompt_posts set ranking_kind = 'power_rankings' where template_kind = 'power_rankings';

create function private.default_ranking_kind()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.template_kind = 'power_rankings' and new.ranking_kind is null then
    new.ranking_kind := 'power_rankings';
  end if;
  return new;
end;
$$;

create trigger prompt_posts_default_ranking_kind
  before insert on public.prompt_posts
  for each row execute function private.default_ranking_kind();

revoke all on function private.default_ranking_kind() from public, anon, authenticated;

-- The update card a player publishes from the list editor (0211). It is a
-- prompt_posts row so it shares the take card, replies and notifications.
alter table public.prompt_posts
  drop constraint prompt_posts_template_kind_check,
  add constraint prompt_posts_template_kind_check
    check (template_kind in (
      'picks', 'game_pick', 'weekly_picks', 'weekly_awards', 'bold_predictions',
      'stat_leader', 'ranking', 'power_rankings', 'ranking_update', 'custom_multi'
    )),
  add constraint prompt_posts_ranking_update_check
    check (template_kind <> 'ranking_update' or (is_opinion and ranking_kind is not null));

-- ------------------------------------------------------------------ helpers --

-- The 32 nflverse team codes the Power Rankings options use.
create function private.nfl_team_codes()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'ARI','ATL','BAL','BUF','CAR','CHI','CIN','CLE','DAL','DEN','DET','GB','HOU','IND','JAX','KC',
    'LA','LAC','LV','MIA','MIN','NE','NO','NYG','NYJ','PHI','PIT','SEA','SF','TB','TEN','WAS'
  ]::text[];
$$;

-- A list's ordered contents, as team codes or player ids.
create function private.ranking_items(p_version uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_agg(coalesce(i.team_code, i.player_id) order by i.place)
    from public.ranking_list_items i
   where i.version_id = p_version;
$$;

-- Raises unless p_items is a valid ordered list for the kind: an allowed
-- length, no blanks or repeats, and every item a real team / player of the
-- right position.
create function private.ranking_check_items(p_kind text, p_items text[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind public.ranking_list_kinds;
  v_count integer := coalesce(array_length(p_items, 1), 0);
begin
  select * into v_kind from public.ranking_list_kinds where id = p_kind;
  if not found then
    raise exception 'unknown_ranking_kind' using errcode = '22023';
  end if;
  if v_count = 0 or not (v_count::smallint = any (v_kind.sizes)) then
    raise exception 'invalid_ranking_size' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_items) i where i is null or i = '')
     or (select count(distinct i) from unnest(p_items) i) <> v_count then
    raise exception 'invalid_ranking_items' using errcode = '22023';
  end if;
  if v_kind.item_kind = 'team' then
    if exists (select 1 from unnest(p_items) i where not (i = any (private.nfl_team_codes()))) then
      raise exception 'invalid_ranking_items' using errcode = '22023';
    end if;
  elsif (select count(*) from prompts_private.nfl_players
          where player_id = any (p_items) and position = v_kind.player_position) <> v_count then
    raise exception 'invalid_ranking_items' using errcode = '22023';
  end if;
end;
$$;

-- Replaces a version's items. The caller has already validated them.
create function private.ranking_replace_items(p_version uuid, p_kind text, p_items text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_team boolean := (select item_kind = 'team' from public.ranking_list_kinds where id = p_kind);
begin
  delete from public.ranking_list_items where version_id = p_version;
  insert into public.ranking_list_items (version_id, place, team_code, player_id)
  select p_version, t.ord::smallint,
         case when v_is_team then t.item end,
         case when not v_is_team then t.item end
    from unnest(p_items) with ordinality as t(item, ord);
end;
$$;

-- The player's list for a kind, created on first use and locked for the rest
-- of the transaction so concurrent saves serialise.
create function private.ranking_ensure_list(p_profile uuid, p_kind text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list uuid;
begin
  insert into public.ranking_lists (profile_id, kind) values (p_profile, p_kind)
  on conflict (profile_id, kind) do nothing;
  select id into v_list from public.ranking_lists
   where profile_id = p_profile and kind = p_kind for update;
  return v_list;
end;
$$;

-- Appends an empty version and makes it current; the caller fills the items.
create function private.ranking_new_version(p_list uuid, p_source text, p_post uuid, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version uuid;
begin
  insert into public.ranking_list_versions (list_id, version_no, source, post_id, note)
  select p_list, coalesce(max(version_no), 0) + 1, p_source, p_post, p_note
    from public.ranking_list_versions where list_id = p_list
  returning id into v_version;
  update public.ranking_lists set current_version_id = v_version where id = p_list;
  return v_version;
end;
$$;

revoke all on function private.nfl_team_codes() from public, anon, authenticated;
revoke all on function private.ranking_items(uuid) from public, anon, authenticated;
revoke all on function private.ranking_check_items(text, text[]) from public, anon, authenticated;
revoke all on function private.ranking_replace_items(uuid, text, text[]) from public, anon, authenticated;
revoke all on function private.ranking_ensure_list(uuid, text) from public, anon, authenticated;
revoke all on function private.ranking_new_version(uuid, text, uuid, text) from public, anon, authenticated;
