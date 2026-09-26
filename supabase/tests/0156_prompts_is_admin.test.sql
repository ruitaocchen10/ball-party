-- Tests for prompts.is_admin (0156): the page-level admin gate reads the
-- same allowlist the write RPCs enforce.

begin;
select plan(4);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('alice', tests.mkuser('alice'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

-- Same helpers as 0095's test: tests.act_as doesn't put an email in its
-- synthetic JWT, and is_admin() matches on auth.jwt()->>'email'.
create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$
  select email from auth.users where id = p_id;
$$;

create function tests.act_as_with_email(p_id uuid) returns void
language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(p_id))::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end $$;

select tests.act_as_with_email((select v from tests.fx where k = 'admin'));
select is(prompts.is_admin(), true, 'an email on the allowlist is an admin');

select tests.act_as_with_email((select v from tests.fx where k = 'alice'));
select is(prompts.is_admin(), false, 'a signed-in email off the allowlist is not');

select tests.act_as((select v from tests.fx where k = 'alice'));
select is(prompts.is_admin(), false, 'a session with no email claim is not');

select tests.act_as_admin();
select ok(
  not has_function_privilege('anon', 'prompts.is_admin()', 'EXECUTE'),
  'anon cannot execute it'
);

select * from finish();
rollback;
