-- Device tokens for iOS push (GitHub #171, part 3 of 4).
--
-- The server's record of which devices a user can be pushed to. This migration
-- sends nothing; the sender (#172) reads these rows. A token identifies one
-- install on one APNs environment, so it is unique on (platform, environment,
-- token) and registering it from a different account moves it: the next person
-- to sign in on a device must not inherit the previous person's pushes.
--
-- RLS is on and nothing is granted to clients; they use only the RPCs below.

create table public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  token       text not null check (length(token) between 16 and 512),
  platform    text not null default 'ios' check (platform in ('ios')),
  -- Which APNs host the token is valid for: a debug build's token only works
  -- against the sandbox, a TestFlight or App Store build's only against production.
  environment text not null check (environment in ('sandbox', 'production')),
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);

create unique index device_tokens_token_idx on public.device_tokens (platform, environment, token);
create index device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
revoke all on table public.device_tokens from public, anon, authenticated;

-- Called on every launch and whenever APNs hands the app a new token, so
-- last_seen says when the device was last known to be alive.
create function public.register_device_token(
  p_token       text,
  p_environment text,
  p_platform    text default 'ios'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  insert into public.device_tokens (user_id, token, platform, environment)
  values (v_me, p_token, p_platform, p_environment)
  on conflict (platform, environment, token)
  do update set user_id = excluded.user_id, last_seen = now();
end;
$$;

-- Only removes the caller's own row, in either environment: sign-out calls this
-- with the token it last registered. Returns whether a row was removed.
create function public.unregister_device_token(p_token text, p_platform text default 'ios')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_removed integer;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  delete from public.device_tokens
   where user_id = v_me and token = p_token and platform = p_platform;
  get diagnostics v_removed = row_count;
  return v_removed > 0;
end;
$$;

-- For the sender (#172): APNs said these tokens are no longer valid
-- (BadDeviceToken, Unregistered), so stop sending to them. Service role only.
create function public.delete_device_tokens(p_tokens text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_removed integer;
begin
  delete from public.device_tokens where token = any (p_tokens);
  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

revoke all on function public.register_device_token(text, text, text) from public, anon;
revoke all on function public.unregister_device_token(text, text) from public, anon;
revoke all on function public.delete_device_tokens(text[]) from public, anon, authenticated;
grant execute on function public.register_device_token(text, text, text) to authenticated;
grant execute on function public.unregister_device_token(text, text) to authenticated;
grant execute on function public.delete_device_tokens(text[]) to service_role;
