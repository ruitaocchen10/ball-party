-- Bold Predictions backend: an admin-created, opinion-only weekly post whose
-- answers are free-text predictions rather than slot choices. Each viewer
-- writes up to five, each tagged with exactly one target (a matchup, a team or
-- a player). They stay private to their author until the post locks, then the
-- whole set is revealed together. No UI here; no grading either — the post is
-- is_opinion, which do_resolve (0111) already refuses.
--
-- Hidden-until-lock follows the same split 0094 uses for prompt_responses: the
-- table is readable only as your own rows, and is deliberately NOT in the
-- Realtime publication (Realtime replicates whole rows regardless of a
-- subscriber's RLS grant). The reveal is a security-definer read RPC with its
-- own lock check, like prompts.revealed_responses (0103/0112).

-- ------------------------------------------------------------------- kind --

-- A bold_predictions post has no slots and is never graded, so it must be an
-- opinion post — same shape of guard as power_rankings (0114).
alter table public.prompt_posts
  drop constraint prompt_posts_template_kind_check,
  add constraint prompt_posts_template_kind_check
    check (template_kind in ('picks', 'game_pick', 'weekly_picks', 'stat_leader', 'ranking', 'power_rankings', 'custom_multi', 'bold_predictions')),
  add constraint prompt_posts_bold_predictions_opinion_check
    check (template_kind <> 'bold_predictions' or is_opinion);

-- ------------------------------------------------------------------ table --

create table public.bold_predictions (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.prompt_posts (id) on delete cascade,
  author_id   uuid not null references public.profiles (id),
  body        text not null check (char_length(body) between 1 and 280 and body = btrim(body)),
  -- Exactly one required tag. target_id is an nflverse game id for 'matchup',
  -- a team code for 'team', a player id for 'player'. Validated on write by
  -- prompts_private.validate_bold_target, not by a constraint, because the
  -- check reads other tables.
  target_type text not null check (target_type in ('matchup', 'team', 'player')),
  target_id   text not null check (target_id <> '' and target_id = btrim(target_id)),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
  -- A later hit/miss result is a plain `add column` (nullable), which needs no
  -- rewrite of this table or its RPCs.
);

create index bold_predictions_post_id on public.bold_predictions (post_id);
create index bold_predictions_target on public.bold_predictions (target_type, target_id);
create index bold_predictions_author_post on public.bold_predictions (author_id, post_id);

-- At most five per author per post, enforced on every insert path. The
-- advisory lock serializes concurrent inserts for the same (post, author),
-- which a plain count-then-insert would race past.
create function prompts_private.bold_predictions_cap()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.post_id::text || ':' || new.author_id::text, 0));
  if (select count(*) from public.bold_predictions
       where post_id = new.post_id and author_id = new.author_id) >= 5 then
    raise exception 'too_many_predictions' using errcode = '54000';
  end if;
  return new;
end;
$$;

create trigger bold_predictions_cap
  before insert on public.bold_predictions
  for each row execute function prompts_private.bold_predictions_cap();

-- -------------------------------------------------------------------- RLS --

alter table public.bold_predictions enable row level security;

-- Own rows only. Other authors' predictions come out through
-- prompts.bold_predictions_for_post, and only after lock.
create policy bold_predictions_select_own on public.bold_predictions
  for select to authenticated using (author_id = auth.uid());

revoke all on table public.bold_predictions from public, anon, authenticated;
grant select on public.bold_predictions to authenticated;
-- No write grants or policies: every write goes through the RPCs below.

-- ------------------------------------------------------------ validation --

-- Valid team codes are nflverse's, as listed in webapp's staticOptionPools
-- TEAMS (the Rams are 'LA').
create function prompts_private.is_valid_team_code(p_code text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_code = any (array[
    'BUF','MIA','NE','NYJ','KC','LV','LAC','DEN','BAL','CIN','CLE','PIT','HOU','IND','JAX','TEN',
    'SEA','SF','LA','ARI','PHI','DAL','NYG','WAS','CHI','DET','GB','MIN','ATL','CAR','NO','TB'
  ]);
$$;

-- Any non-empty id is accepted until the player directory lands. When it does,
-- tighten this one function to look the id up there; callers don't change.
create function prompts_private.is_valid_player_id(p_id text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(btrim(p_id), '') <> '';
$$;

-- A post carries no week of its own. Its week is the one whose first kickoff
-- follows lock_at (lock_at is set before that week's first kickoff).
create function prompts_private.bold_prediction_week(p_lock_at timestamptz)
returns table (season smallint, week smallint)
language sql
stable
security definer
set search_path = ''
as $$
  select g.season, g.week
    from public.nfl_games g
   where g.kickoff >= p_lock_at
   order by g.kickoff
   limit 1;
$$;

create function prompts_private.validate_bold_target(p_post public.prompt_posts, p_type text, p_id text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_type = 'matchup' then
    if not exists (
      select 1
        from public.nfl_games g
        join prompts_private.bold_prediction_week(p_post.lock_at) w
          on w.season = g.season and w.week = g.week
       where g.id = p_id
    ) then
      raise exception 'invalid_target' using errcode = '22023', detail = 'matchup';
    end if;
  elsif p_type = 'team' then
    if not prompts_private.is_valid_team_code(p_id) then
      raise exception 'invalid_target' using errcode = '22023', detail = 'team';
    end if;
  elsif p_type = 'player' then
    if not prompts_private.is_valid_player_id(p_id) then
      raise exception 'invalid_target' using errcode = '22023', detail = 'player';
    end if;
  else
    raise exception 'invalid_target' using errcode = '22023', detail = 'target_type';
  end if;
end;
$$;

-- ----------------------------------------------------------------- writes --

-- Shared preamble: a signed-in, non-guest caller and an open bold_predictions
-- post that has not reached lock_at. Locks the post row so a write cannot slip
-- in beside a concurrent lock.
create function prompts_private.bold_writable_post(p_post_id uuid)
returns public.prompt_posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts;
begin
  if auth.uid() is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_post from public.prompt_posts where id = p_post_id for share;
  if not found then
    raise exception 'post_not_found' using errcode = 'P0002';
  end if;
  if v_post.template_kind <> 'bold_predictions' then
    raise exception 'not_bold_predictions' using errcode = '22023';
  end if;
  if v_post.status <> 'open' or now() >= v_post.lock_at then
    raise exception 'post_locked' using errcode = '55000';
  end if;
  return v_post;
end;
$$;

create function prompts.add_bold_prediction(p_post_id uuid, p_body text, p_target_type text, p_target_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.prompt_posts := prompts_private.bold_writable_post(p_post_id);
  v_id   uuid;
begin
  perform prompts_private.validate_bold_target(v_post, p_target_type, btrim(p_target_id));

  insert into public.bold_predictions (post_id, author_id, body, target_type, target_id)
  values (p_post_id, auth.uid(), btrim(p_body), p_target_type, btrim(p_target_id))
  returning id into v_id;
  return v_id;
end;
$$;

create function prompts.edit_bold_prediction(p_prediction_id uuid, p_body text, p_target_type text, p_target_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post_id uuid;
  v_post    public.prompt_posts;
begin
  -- Absent and not-yours look identical, so a caller cannot probe for other
  -- authors' prediction ids.
  select post_id into v_post_id from public.bold_predictions
   where id = p_prediction_id and author_id = auth.uid();
  if not found then
    raise exception 'prediction_not_found' using errcode = 'P0002';
  end if;

  v_post := prompts_private.bold_writable_post(v_post_id);
  perform prompts_private.validate_bold_target(v_post, p_target_type, btrim(p_target_id));

  update public.bold_predictions
     set body = btrim(p_body), target_type = p_target_type, target_id = btrim(p_target_id), updated_at = now()
   where id = p_prediction_id;
end;
$$;

create function prompts.delete_bold_prediction(p_prediction_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post_id uuid;
begin
  select post_id into v_post_id from public.bold_predictions
   where id = p_prediction_id and author_id = auth.uid();
  if not found then
    raise exception 'prediction_not_found' using errcode = 'P0002';
  end if;

  perform prompts_private.bold_writable_post(v_post_id);
  delete from public.bold_predictions where id = p_prediction_id;
end;
$$;

-- ------------------------------------------------------------------ reads --

create function prompts.my_bold_predictions(p_post_id uuid)
returns setof public.bold_predictions
language sql
security definer
set search_path = ''
stable
as $$
  select * from public.bold_predictions
   where post_id = p_post_id and author_id = auth.uid()
   order by created_at, id;
$$;

-- Everyone's predictions once the post has locked; before that, only the
-- caller's own. Mirrors revealed_responses' lock test (lock_at passed, or the
-- post was locked/resolved by status). A void post is not revealed early.
create function prompts.bold_predictions_for_post(p_post_id uuid)
returns setof public.bold_predictions
language sql
security definer
set search_path = ''
stable
as $$
  select bp.*
    from public.bold_predictions bp
    join public.prompt_posts p on p.id = bp.post_id
   where bp.post_id = p_post_id
     and (
       bp.author_id = auth.uid()
       or p.lock_at <= now()
       or p.status in ('locked', 'resolved')
     )
   order by bp.created_at, bp.id;
$$;

-- ----------------------------------------------------------------- grants --

revoke all on function prompts_private.bold_predictions_cap()                         from public, anon, authenticated;
revoke all on function prompts_private.is_valid_team_code(text)                       from public, anon, authenticated;
revoke all on function prompts_private.is_valid_player_id(text)                       from public, anon, authenticated;
revoke all on function prompts_private.bold_prediction_week(timestamptz)              from public, anon, authenticated;
revoke all on function prompts_private.validate_bold_target(public.prompt_posts, text, text) from public, anon, authenticated;
revoke all on function prompts_private.bold_writable_post(uuid)                       from public, anon, authenticated;

revoke all on function prompts.add_bold_prediction(uuid, text, text, text)            from public, anon;
revoke all on function prompts.edit_bold_prediction(uuid, text, text, text)           from public, anon;
revoke all on function prompts.delete_bold_prediction(uuid)                           from public, anon;
revoke all on function prompts.my_bold_predictions(uuid)                              from public, anon;
revoke all on function prompts.bold_predictions_for_post(uuid)                        from public;

grant execute on function prompts.add_bold_prediction(uuid, text, text, text)         to authenticated;
grant execute on function prompts.edit_bold_prediction(uuid, text, text, text)        to authenticated;
grant execute on function prompts.delete_bold_prediction(uuid)                        to authenticated;
grant execute on function prompts.my_bold_predictions(uuid)                           to authenticated;
-- Revealed predictions are public like the Huddle itself (0112).
grant execute on function prompts.bold_predictions_for_post(uuid)                     to anon, authenticated;
