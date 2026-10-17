-- Tests for 0220: reports, the admin queue, block hiding and the word filter.

begin;
select plan(22);
\ir support/harness.psql

select tests.act_as_admin();
delete from public.prompt_posts;

insert into tests.fx (k, v) values
  ('admin', tests.mkuser('admin')),
  ('alice', tests.mkuser('alice')),
  ('bob',   tests.mkuser('bob')),
  ('cy',    tests.mkuser('cy')),
  ('guest', tests.mkguest('guest'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$ select email from auth.users where id = p_id; $$;

create function tests.act_as_prompts_admin() returns void
language plpgsql as $$
declare v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(v_id))::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function tests.who(p_k text) returns uuid
language sql stable as $$ select v from tests.fx where k = p_k $$;

insert into public.prompt_posts (id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, status) values
  ('10000000-0000-0000-0000-000000000001', 'game_pick', 'T', tests.who('admin'), 'Post', 'T', 'T', now() + interval '2 days', 'open');
insert into public.prompt_comments (id, post_id, author_id, body) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', tests.who('bob'), 'Bob take'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', tests.who('cy'),  'Cy take'),
  ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', tests.who('alice'), 'Alice take');

-- Everyone sees every take to start with, signed out included.
set local role anon;
select is((select count(*)::int from public.prompt_comments), 3, 'signed out sees all takes');

-- Reporting.
select tests.act_as(tests.who('alice'));
select lives_ok($$select public.report_take('30000000-0000-0000-0000-000000000001', 'harassment', 'rude')$$, 'alice reports bob''s take');
select lives_ok($$select public.report_take('30000000-0000-0000-0000-000000000001', 'harassment', 'again')$$, 'reporting twice is a no-op');
select throws_ok($$select public.report_take('30000000-0000-0000-0000-000000000003', 'spam')$$, '42501', 'cannot_report_self', 'cannot report own take');
select throws_ok($$select public.report_take('30000000-0000-0000-0000-000000000002', 'bogus')$$, '23514', null, 'unknown reason refused');
select is((select count(*)::int from public.prompt_comments where id = '30000000-0000-0000-0000-000000000001'), 0, 'reported take is hidden from the reporter');
select is((select count(*)::int from public.prompt_comments), 2, 'reporter still sees the rest');

select tests.act_as(tests.who('cy'));
select is((select count(*)::int from public.prompt_comments), 3, 'others still see the reported take');
select lives_ok($$select public.report_profile(tests.who('bob'), 'hate')$$, 'cy reports bob''s profile');
select throws_ok($$select public.report_profile(tests.who('cy'), 'hate')$$, 'P0002', 'profile_not_found', 'cannot report self profile');

select tests.act_as_guest(tests.who('guest'));
select throws_ok($$select public.report_take('30000000-0000-0000-0000-000000000002', 'spam')$$, '42501', 'account_required', 'guest cannot report');

-- Reports are closed to players.
select tests.act_as(tests.who('alice'));
select is((select count(*)::int from public.content_reports), 0, 'players cannot read reports');
select throws_ok($$select * from public.admin_list_reports()$$, '42501', 'not_admin', 'players cannot list the queue');

-- The queue.
select tests.act_as_prompts_admin();
select is((select count(*)::int from public.admin_list_reports()), 2, 'admin sees both open reports');
select is((select target_report_count::int from public.admin_list_reports() where kind = 'take'), 2, 'queue shows the target''s report count');

select public.admin_resolve_report((select id from public.admin_list_reports() where kind = 'take'), 'remove');
select is((select count(*)::int from public.admin_list_reports()), 1, 'removing closes the take report');

select tests.act_as(tests.who('cy'));
select is((select count(*)::int from public.prompt_comments where id = '30000000-0000-0000-0000-000000000001'), 0, 'a removed take is gone for everyone');

select tests.act_as_prompts_admin();
select public.admin_resolve_report((select id from public.admin_list_reports() where kind = 'profile'), 'ban');
select tests.act_as_admin();
select ok((select banned_until > now() from auth.users where id = tests.who('bob')), 'ban stops sign in');
select tests.act_as_prompts_admin();
select is((select count(*)::int from public.admin_list_reports()), 0, 'queue is empty');

-- Blocking hides takes both ways.
select tests.act_as(tests.who('alice'));
select public.block_user(tests.who('cy'));
select is((select count(*)::int from public.prompt_comments where author_id = tests.who('cy')), 0, 'blocker no longer sees the blocked player''s takes');
select tests.act_as(tests.who('cy'));
select is((select count(*)::int from public.prompt_comments where author_id = tests.who('alice')), 0, 'the blocked player no longer sees the blocker''s takes');

-- The word filter.
select tests.act_as(tests.who('alice'));
select throws_ok($$select prompts.post_comment('10000000-0000-0000-0000-000000000001', 'you should KYS')$$, '22023', 'content_not_allowed', 'filter refuses a banned term');

select * from finish();
rollback;
