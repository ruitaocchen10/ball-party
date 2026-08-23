-- Sabotage draft: a disconnected seat remains part of the match.
--
-- This deliberately adds only the latched absence bit.  The two game effects
-- of leaving are already represented by the prior migrations: an unmade pick
-- is filled by expire's random draw, and an unmade guess is simply no row in
-- the guess log.  Keeping that routing means neither outcome has a competing
-- "absent player" implementation to drift from the ordinary game rule.

alter table public.sabotage_draft_players
  add column absent boolean not null default false;

-- The client calls this after its Realtime presence layer observes that this
-- seat has gone away.  It is intentionally scoped to the caller's own seat:
-- a participant cannot remove another player from the table by claiming they
-- disconnected.
create function sabotage_draft.mark_absent(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  update public.sabotage_draft_players sp
     set absent = true
    from public.matches mt
   where sp.match_id = p_match_id
     and sp.user_id = v_user
     and mt.id = sp.match_id
     and mt.status = 'playing'::public.match_status;

  if not found then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
end;
$$;

-- tick is already the live client's clock poll and reconnect state read.  A
-- successful tick is therefore the first ordinary ping after reconnecting;
-- it clears absence before continuing through the exact same expiry path as
-- every other player.  No rehydration endpoint or alternate round transition
-- is needed.
create or replace function sabotage_draft.tick(p_match_id uuid)
returns sabotage_draft.round
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  update public.sabotage_draft_players sp
     set absent = false
    from public.matches mt
   where sp.match_id = p_match_id
     and sp.user_id = v_user
     and mt.id = sp.match_id
     and mt.status = 'playing'::public.match_status;

  if not found then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  perform sabotage_draft_private.expire(p_match_id);
  return sabotage_draft_private.round_of(p_match_id);
end;
$$;

grant execute on function sabotage_draft.mark_absent(uuid) to authenticated;
revoke all on function sabotage_draft.mark_absent(uuid) from public, anon;
