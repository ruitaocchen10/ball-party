-- Reporting and moderation for user-generated content (App Store guideline
-- 1.2). Players can report a take or reply and a player's profile; the one
-- admin reviews the queue and can dismiss, remove the take, or ban the player.
-- Blocking now hides a blocked player's takes from the blocker, and the
-- blocker's from them. A reported take is hidden from its reporter at once.
-- A small word filter refuses obvious abuse at write time.

alter table public.prompt_comments
  add column removed_at timestamptz;

-- ----------------------------------------------------------------- reports --

create table public.content_reports (
  id             uuid primary key default gen_random_uuid(),
  reporter_id    uuid not null references public.profiles (id) on delete cascade,
  -- The take or reply reported; null for a profile report.
  comment_id     uuid references public.prompt_comments (id) on delete cascade,
  -- The author of the take, or the profile reported.
  target_user_id uuid not null references public.profiles (id) on delete cascade,
  reason         text not null check (reason in ('spam', 'harassment', 'hate', 'sexual', 'violence', 'other')),
  details        text check (details is null or char_length(details) <= 500),
  status         text not null default 'open' check (status in ('open', 'dismissed', 'removed', 'banned')),
  created_at     timestamptz not null default now(),
  resolved_at    timestamptz,
  check (reporter_id <> target_user_id)
);

-- One report per reporter per target; reporting again changes nothing.
create unique index content_reports_take_once
  on public.content_reports (reporter_id, comment_id) where comment_id is not null;
create unique index content_reports_profile_once
  on public.content_reports (reporter_id, target_user_id) where comment_id is null;
create index content_reports_status_created on public.content_reports (status, created_at);
create index content_reports_target on public.content_reports (target_user_id);

alter table public.content_reports enable row level security;
revoke all on table public.content_reports from public, anon, authenticated;

-- ------------------------------------------------------------- visibility --

-- Whether the caller may see a take: not removed by the admin, not by someone
-- in a block with the caller (either direction), and not one the caller
-- reported. Runs as the owner because friendships and reports are closed to
-- players. Signed-out readers see everything not removed.
create function public.comment_visible(p_comment_id uuid, p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    not exists (select 1 from public.prompt_comments c where c.id = p_comment_id and c.removed_at is not null)
    and (
      auth.uid() is null
      or (
        not exists (
          select 1 from public.friendships f
           where f.status = 'blocked'
             and least(f.requester_id, f.addressee_id) = least(auth.uid(), p_author_id)
             and greatest(f.requester_id, f.addressee_id) = greatest(auth.uid(), p_author_id)
        )
        and not exists (
          select 1 from public.content_reports r
           where r.reporter_id = auth.uid() and r.comment_id = p_comment_id
        )
      )
    );
$$;
revoke all on function public.comment_visible(uuid, uuid) from public;
grant execute on function public.comment_visible(uuid, uuid) to anon, authenticated;

drop policy prompt_comments_select_public on public.prompt_comments;
create policy prompt_comments_select_public on public.prompt_comments
  for select to anon, authenticated using (
    exists (select 1 from public.prompt_posts p where p.id = prompt_comments.post_id)
    and public.comment_visible(prompt_comments.id, prompt_comments.author_id)
  );

-- ------------------------------------------------------------------ report --

create function private.report_caller()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null
     or not exists (
       select 1 from public.profiles p
        where p.id = v_me and not p.is_guest and p.deleted_at is null
     ) then
    raise exception 'account_required' using errcode = '42501';
  end if;
  return v_me;
end;
$$;
revoke all on function private.report_caller() from public, anon, authenticated;

create function public.report_take(p_comment_id uuid, p_reason text, p_details text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me     uuid := private.report_caller();
  v_author uuid;
begin
  -- Reporting the same take again changes nothing. It is checked first
  -- because the first report already hides the take from its reporter.
  if exists (select 1 from public.content_reports r where r.reporter_id = v_me and r.comment_id = p_comment_id) then
    return;
  end if;

  select author_id into v_author from public.prompt_comments c
   where c.id = p_comment_id and public.comment_visible(c.id, c.author_id);
  if v_author is null then
    raise exception 'take_not_found' using errcode = 'P0002';
  end if;
  if v_author = v_me then
    raise exception 'cannot_report_self' using errcode = '42501';
  end if;

  insert into public.content_reports (reporter_id, comment_id, target_user_id, reason, details)
  values (v_me, p_comment_id, v_author, p_reason, nullif(trim(coalesce(p_details, '')), ''))
  on conflict do nothing;
end;
$$;

create function public.report_profile(p_user_id uuid, p_reason text, p_details text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.report_caller();
begin
  if p_user_id is null or p_user_id = v_me
     or not exists (select 1 from public.profiles where id = p_user_id and not is_guest and deleted_at is null) then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  insert into public.content_reports (reporter_id, comment_id, target_user_id, reason, details)
  values (v_me, null, p_user_id, p_reason, nullif(trim(coalesce(p_details, '')), ''))
  on conflict do nothing;
end;
$$;

revoke all on function public.report_take(uuid, text, text) from public, anon;
grant execute on function public.report_take(uuid, text, text) to authenticated;
revoke all on function public.report_profile(uuid, text, text) from public, anon;
grant execute on function public.report_profile(uuid, text, text) to authenticated;

-- ------------------------------------------------------------------- admin --

-- The queue, oldest first. Every report row is returned with what the admin
-- needs to judge it: the reported text (even if removed) and how many reports
-- the same player has received.
create function public.admin_list_reports(p_status text default 'open')
returns table (
  id            uuid,
  kind          text,
  reason        text,
  details       text,
  status        text,
  created_at    timestamptz,
  reporter_name text,
  target_user_id uuid,
  target_name   text,
  target_username text,
  comment_id    uuid,
  comment_body  text,
  post_id       uuid,
  target_report_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not prompts_private.is_admin() then
    raise exception 'not_admin' using errcode = '42501';
  end if;

  return query
  select r.id,
         case when r.comment_id is null then 'profile' else 'take' end,
         r.reason, r.details, r.status, r.created_at,
         rp.display_name, r.target_user_id, tp.display_name, tp.username,
         r.comment_id, c.body, c.post_id,
         (select count(*) from public.content_reports x where x.target_user_id = r.target_user_id)
    from public.content_reports r
    join public.profiles rp on rp.id = r.reporter_id
    join public.profiles tp on tp.id = r.target_user_id
    left join public.prompt_comments c on c.id = r.comment_id
   where r.status = p_status
   order by r.created_at;
end;
$$;

-- dismiss: nothing wrong. remove: take the reported take down (profile
-- reports have nothing to remove and are only closed). ban: remove all of the
-- player's takes and stop them signing in. Either way every open report on the
-- same take or profile is closed with the decision.
create function public.admin_resolve_report(p_report_id uuid, p_action text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_report public.content_reports;
  v_status text;
begin
  if not prompts_private.is_admin() then
    raise exception 'not_admin' using errcode = '42501';
  end if;
  if p_action not in ('dismiss', 'remove', 'ban') then
    raise exception 'invalid_action' using errcode = '22023';
  end if;

  select * into v_report from public.content_reports where id = p_report_id;
  if not found then
    raise exception 'report_not_found' using errcode = 'P0002';
  end if;

  v_status := case p_action when 'dismiss' then 'dismissed' when 'remove' then 'removed' else 'banned' end;

  if p_action = 'remove' and v_report.comment_id is not null then
    update public.prompt_comments set removed_at = coalesce(removed_at, now())
     where id = v_report.comment_id;
  elsif p_action = 'ban' then
    update public.prompt_comments set removed_at = coalesce(removed_at, now())
     where author_id = v_report.target_user_id;
    update auth.users set banned_until = now() + interval '100 years'
     where id = v_report.target_user_id;
  end if;

  update public.content_reports
     set status = v_status, resolved_at = now()
   where status = 'open'
     and (
       id = p_report_id
       or (p_action = 'ban' and target_user_id = v_report.target_user_id)
       or (comment_id is not null and comment_id = v_report.comment_id)
       or (comment_id is null and v_report.comment_id is null
           and target_user_id = v_report.target_user_id)
     );
end;
$$;

revoke all on function public.admin_list_reports(text) from public, anon;
grant execute on function public.admin_list_reports(text) to authenticated;
revoke all on function public.admin_resolve_report(uuid, text) from public, anon;
grant execute on function public.admin_resolve_report(uuid, text) to authenticated;

-- ------------------------------------------------------------- word filter --

-- Whole words and phrases a take may not contain, matched case-insensitively.
-- The admin maintains the list in SQL; it is not readable by players.
create table private.banned_terms (
  term text primary key check (term = lower(term) and char_length(term) between 2 and 60)
);
insert into private.banned_terms (term) values ('kys'), ('kill yourself');

create function private.contains_banned_term(p_text text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from private.banned_terms t
     where p_text ~* ('\m' || regexp_replace(t.term, '([^a-z0-9 ])', '\\\1', 'g') || '\M')
  );
$$;
revoke all on function private.contains_banned_term(text) from public, anon, authenticated;

-- A trigger rather than a check in each writer: takes are written by
-- post_comment, by answering a prompt, and by the ranking-list prompts.
create function private.prompt_comments_filter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.body is not null and private.contains_banned_term(new.body) then
    raise exception 'content_not_allowed' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function private.prompt_comments_filter() from public, anon, authenticated;

create trigger prompt_comments_filter
  before insert or update of body on public.prompt_comments
  for each row execute function private.prompt_comments_filter();
