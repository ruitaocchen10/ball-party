-- Lets the webapp ask the database "is the caller a prompts admin?" so the
-- /admin/* layout gates on the same prompts_private.admin_config allowlist
-- that create_post / resolve_post / void_post already enforce (0095).
-- Before this, the layout matched the caller's email against a separate
-- PROMPTS_ADMIN_EMAILS env var, so the page gate and the RPC gate could
-- disagree: an email in only one of them either reached a page whose writes
-- all failed, or held write access with no page to use it from.
--
-- prompts_private isn't reachable from PostgREST (0094's schema revoke), so
-- this is a thin prompts.* wrapper, same shape as the other admin-facing
-- entry points. It returns only a boolean about the caller's own email and
-- never the allowlist, so granting it to every signed-in user leaks nothing.
create function prompts.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select prompts_private.is_admin();
$$;

revoke all on function prompts.is_admin() from public, anon;
grant execute on function prompts.is_admin() to authenticated;
