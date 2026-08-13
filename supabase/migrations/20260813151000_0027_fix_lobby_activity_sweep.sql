-- 0026's loop variable is named r. Give the nested runs relation a distinct
-- name so PL/pgSQL does not resolve it as the unassigned record variable.
create or replace function private.sweep_inactive_lobbies()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select l.id
      from public.lobbies l
     where l.closed_at is null
       and not exists (
         select 1 from public.runs active_run
          where active_run.lobby_id = l.id
            and active_run.status = 'active'
       )
       and not exists (
         select 1 from public.lobby_members m
          where m.lobby_id = l.id
            and m.left_at is null
            and m.last_seen_at >= now() - interval '20 minutes'
       )
  loop
    perform private.close_lobby_internal(r.id);
  end loop;
end;
$$;
