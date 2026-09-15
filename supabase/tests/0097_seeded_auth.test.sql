-- Local seed accounts must be complete enough for GoTrue password login.
-- GoTrue scans confirmation_token as a string; a NULL token turns sign-in
-- into a 500 even when the account is already confirmed.

begin;
select plan(1);

select is(
  (select count(*)::int
     from auth.users
    where email in ('demo@ballparty.local', 'curator@ballparty.local', 'tasha@ballparty.local')
      and email_confirmed_at is not null
      and confirmation_token is not null
      and email_change is not null
      and email_change_token_new is not null
      and recovery_token is not null),
  3,
  'the confirmed local demo accounts have GoTrue’s non-null password-login fields'
);

select * from finish();
rollback;
