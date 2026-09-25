-- Signed-out visitors can play the solo games as an anonymous guest, so the
-- nightly guest cleanup (0016) has to be able to remove what such a guest leaves.
--
-- 0016 deletes an anonymous user only if it has no run_participants row at all,
-- and every solo run inserts one, so a guest who ever played solo was never
-- cleaned up. Deleting the user directly cannot work either: run_participants
-- and match_players reference profiles and each other with NO ACTION, so the
-- solo matches and runs have to go first, matches before runs.
--
-- Two lifetimes, both measured on the run rather than on the guest:
--
--   finished     kept 30 days after it ended. The saved season result lives on the
--                match (season_results cascades from it), so this is also how long
--                a shared result link keeps working.
--   not finished dropped a day after it started. Nobody is coming back to it, and
--                a guest's session is a cookie in one browser.
--
-- Measuring the run, not the user, is what keeps a returning guest's recent run
-- safe: a cookie that is a year old still owns whatever it played yesterday.
--
-- Only solo runs are touched. A party match is shared with other players and a
-- guest that took part in one keeps its history exactly as 0016 left it: the user
-- delete below still requires that no run_participants row remains.

create or replace function private.cleanup_guest_accounts()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stale uuid[];
begin
  select coalesce(array_agg(r.id), '{}')
    into v_stale
    from public.runs r
   where r.mode = 'solo'::public.run_mode
     and exists (
           select 1
             from public.run_participants rp
             join auth.users u on u.id = rp.user_id
            where rp.run_id = r.id and u.is_anonymous
         )
     and not exists (
           select 1
             from public.matches m
            where m.run_id = r.id
              and case when m.status = 'complete'::public.match_status
                       then coalesce(m.ended_at, r.started_at) >= now() - interval '30 days'
                       else r.started_at >= now() - interval '1 day'
                  end
         );

  delete from public.matches where run_id = any (v_stale);
  delete from public.runs where id = any (v_stale);

  delete from auth.users u
   where u.is_anonymous
     and u.created_at < now() - interval '30 days'
     and not exists (select 1 from public.run_participants rp where rp.user_id = u.id);
end;
$$;
