begin;
select plan(1);

\ir support/harness.psql

with google_user as (
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values (
    gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'google-avatar@example.test', '', now(), now(), now(),
    '{"provider":"google","providers":["google"]}'::jsonb,
    '{"full_name":"Google Player","picture":"https://images.example.test/google-avatar.png"}'::jsonb
  )
  returning id
)
insert into tests.fx (k, v)
select 'google_player', id from google_user;

select is(
  (select avatar_url from public.profiles where id = (select v from tests.fx where k = 'google_player')),
  'https://images.example.test/google-avatar.png',
  'a Google picture metadata URL seeds the public profile avatar'
);

select * from finish();
rollback;
