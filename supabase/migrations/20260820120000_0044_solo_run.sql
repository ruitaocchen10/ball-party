-- Solo play, platform side. See issue #32.
--
-- A solo run is the degenerate room: one player, no lobby, nothing to code in
-- and nobody else to wait on. `runs.lobby_id` was `not null` because every run
-- used to hang off a room; it goes nullable here, and a check constraint ties
-- the two facts together so a run is solo exactly when it has no lobby.
--
-- The membership helpers this unlocks are the point of the migration.
-- `private.is_run_member` answered "are you a current member of this run's
-- lobby", which a lobby-less run can never satisfy — a solo player would be
-- locked out of their own run. It gains a second path: no lobby, so ownership
-- falls back to the run's own roster, `run_participants`. `is_match_member`
-- (0010) duplicated the same lobby join rather than calling `is_run_member`;
-- it is rewritten here to delegate, so this is the one place either kind of
-- run's membership is decided.

alter table public.runs
  alter column lobby_id drop not null,
  add constraint runs_solo_has_no_lobby check ((mode = 'solo'::public.run_mode) = (lobby_id is null));

create or replace function private.is_run_member(p_run_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1
    from public.runs r
    where r.id = p_run_id
      and (
        exists (
          select 1 from public.lobby_members m
           where m.lobby_id = r.lobby_id and m.user_id = auth.uid() and m.left_at is null
        )
        -- No lobby to hold membership, so the run's own frozen roster is the
        -- whole answer. Guarded on lobby_id rather than on mode so this reads
        -- as "no lobby" rather than as a second run_mode branch to keep in
        -- sync with the enum.
        or (
          r.lobby_id is null
          and exists (
            select 1 from public.run_participants rp
             where rp.run_id = r.id and rp.user_id = auth.uid()
          )
        )
      )
  );
$$;

-- Delegates rather than re-deriving: a match is a member's iff its run is, so
-- the lobby-vs-solo branch only needs to exist once.
create or replace function private.is_match_member(p_match_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1 from public.matches mt
     where mt.id = p_match_id and private.is_run_member(mt.run_id)
  );
$$;

-- `runs_select_member` (0003, moved in 0004) checked `is_lobby_member(lobby_id)`
-- directly rather than going through `is_run_member` — the one platform policy
-- that didn't. `is_lobby_member(null)` is simply false, which would hide a solo
-- player's own run from them, so this switches it to the helper every sibling
-- table already uses.
drop policy runs_select_member on public.runs;
create policy runs_select_member on public.runs
  for select to authenticated using (private.is_run_member(id));

-- --------------------------------------------------------------- the start --

-- The solo counterpart to `start_run` (0009). No lobby to lock, no host to
-- check, no roster to freeze from current membership — the caller is the
-- whole roster, seated alone.
--
-- Any authenticated session may call this, guest included: the product's rule
-- has only ever been that hosting a room needs an account, never that playing
-- does. `start_run` enforces that boundary because it is the one that opens a
-- room; this function opens nothing for anyone else, so there is no boundary
-- to enforce.
create function public.start_solo_run(p_game text)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_run   public.runs;
  v_match public.matches;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  insert into public.runs (lobby_id, mode)
  values (null, 'solo'::public.run_mode)
  returning * into v_run;

  insert into public.run_participants (run_id, user_id, seat)
  values (v_run.id, v_user, 0);

  insert into public.matches (run_id, game, seq, status)
  values (v_run.id, p_game, 1, 'setup'::public.match_status)
  returning * into v_match;

  return v_match;
end;
$$;

revoke all on function public.start_solo_run(text) from public, anon;
grant execute on function public.start_solo_run(text) to authenticated;
