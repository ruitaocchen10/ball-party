-- The collision breadcrumb records that a guest's play and a credentialed
-- account belong to the same person. 0016 let the account assert that by
-- itself: the RPC proved the named user was a guest and was not the caller,
-- but never that the caller had ever held that guest's session. Any
-- authenticated user could name any guest, and the upsert let them overwrite
-- an existing breadcrumb as well as invent one.
--
-- The real check lived in the sign-in server action, which is the wrong side
-- of the boundary this codebase draws. From docs/architecture/architecture.md:
-- "the RPC derives identity from auth.uid() and validates the move itself,
-- which is what made it trustworthy in the first place — never the server
-- action."
--
-- Nothing reads this table yet, which is exactly why now is the time: its only
-- purpose is to authorise a future reattachment of match history, and a table
-- anyone can write is worthless for that.
--
-- So the assertion is split, and each half is proven by auth.uid():
--
--   1. the guest stakes a claim on itself and receives a nonce
--   2. the account redeems that nonce
--
-- Neither call accepts an identity the caller does not already hold. The nonce
-- is single-use, short-lived, and in practice never leaves the server action
-- that brokers the two steps.

-- A row is now either an open claim or a settled breadcrumb.
alter table public.guest_account_collisions
  alter column account_id drop not null,
  add column claim_nonce uuid unique,
  add column claimed_at  timestamptz;

-- Rows written under 0016 were settled on arrival.
update public.guest_account_collisions
   set claimed_at = created_at
 where account_id is not null and claimed_at is null;

alter table public.guest_account_collisions
  add constraint guest_account_collisions_settled_or_open check (
    (account_id is null     and claim_nonce is not null and claimed_at is null)
    or
    (account_id is not null and claim_nonce is null     and claimed_at is not null)
  );

-- Step 1. Callable only by a guest, and only ever about itself — there is no
-- argument to forge. Re-staking refreshes an open claim; a settled breadcrumb
-- is immutable, which is what stops the overwrite the old version allowed.
create function public.claim_guest_identity()
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_guest uuid := auth.uid();
  v_nonce uuid := gen_random_uuid();
begin
  if v_guest is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (select 1 from auth.users where id = v_guest and is_anonymous) then
    raise exception 'not_a_guest' using errcode = '42501';
  end if;

  insert into public.guest_account_collisions as gac (guest_id, account_id, claim_nonce, claimed_at)
  values (v_guest, null, v_nonce, null)
  on conflict (guest_id) do update
     set claim_nonce = excluded.claim_nonce,
         account_id  = null,
         claimed_at  = null,
         created_at  = now()
   where gac.claimed_at is null;

  -- The filtered DO UPDATE touches nothing when the row is already settled.
  if not found then
    raise exception 'already_settled' using errcode = 'P0001';
  end if;

  return v_nonce;
end;
$$;

-- Step 2. The parameter is a nonce, not an identity: holding it is the proof
-- that the caller held the guest session that minted it. The account side
-- comes from auth.uid() and is not accepted from the caller either.
drop function public.record_guest_account_collision(uuid);

create function public.record_guest_account_collision(p_nonce uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_account uuid := auth.uid();
  v_guest   uuid;
begin
  if v_account is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select guest_id into v_guest
    from public.guest_account_collisions
   where claim_nonce = p_nonce
     and claimed_at is null
     and created_at > now() - interval '1 hour'
     for update;

  -- Unknown, already redeemed, and expired are one answer on purpose: a caller
  -- guessing nonces learns nothing about which of those it hit.
  if not found then
    raise exception 'claim_not_found' using errcode = 'P0001';
  end if;

  if v_guest = v_account then
    raise exception 'not_a_collision' using errcode = '42501';
  end if;

  update public.guest_account_collisions
     set account_id  = v_account,
         claim_nonce = null,
         claimed_at  = now()
   where guest_id = v_guest;
end;
$$;

revoke all on function public.claim_guest_identity() from public, anon;
revoke all on function public.record_guest_account_collision(uuid) from public, anon;
grant execute on function public.claim_guest_identity() to authenticated;
grant execute on function public.record_guest_account_collision(uuid) to authenticated;
