-- Tests for the opinion-prompt flag (0111): is_opinion is a characteristic
-- any template_kind can carry, not a kind of its own, and it must make a
-- post permanently unresolvable rather than merely "not resolved yet."

begin;
select plan(7);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$
  select email from auth.users where id = p_id;
$$;

create function tests.act_as_prompts_admin() returns void
language plpgsql as $$
declare
  v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(v_id))::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end $$;

select tests.act_as_prompts_admin();

-- ------------------------------------------------------------- create_post --

insert into tests.fx (k, v)
select 'opinion_post', prompts.create_post(
  'custom_multi', 'Hot take', 'cap', 'most overrated team this season?', 'crit',
  now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Pick one', 'shape', 'pick', 'points', 15,
    'options', jsonb_build_array(jsonb_build_object('label', 'Team One'), jsonb_build_object('label', 'Team Two'))
  )),
  null::jsonb,
  true
);

select is((select is_opinion from public.prompt_posts where id = (select v from tests.fx where k = 'opinion_post')),
  true, 'create_post records is_opinion when the caller asks for it');

-- ------------------------------------------------------------ do_resolve guard --

select throws_ok(
  format(
    $$ select prompts.resolve_post(%L, jsonb_build_object(%L, jsonb_build_array((select id::text from public.prompt_slot_options where slot_id = %L limit 1)))) $$,
    (select v from tests.fx where k = 'opinion_post'),
    (select id::text from public.prompt_slots where post_id = (select v from tests.fx where k = 'opinion_post')),
    (select id from public.prompt_slots where post_id = (select v from tests.fx where k = 'opinion_post'))
  ),
  '55000', 'opinion_not_resolvable', 'an admin cannot resolve an opinion post even with a well-formed answer'
);

select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'opinion_post')),
  'open', 'the rejected resolve attempt left the post untouched');

-- ------------------------------------------------------- opinion + auto-source --

select throws_ok(
  $$
    select prompts.create_post(
      'picks', 'Picks', 'cap', 'who wins', 'crit', now() + interval '1 day',
      jsonb_build_array(jsonb_build_object(
        'label', 'Winner', 'shape', 'pick', 'points', 10,
        'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
      )),
      jsonb_build_object('provider', 'nflverse', 'rule', 'winner'),
      true
    )
  $$,
  '23514', 'new row for relation "prompt_posts" violates check constraint "prompt_posts_opinion_no_auto_source"',
  'a post cannot be both opinion and carry an nflverse auto-resolve source'
);

-- --------------------------------------------------------------------- void --

select lives_ok(
  format($$ select prompts.void_post(%L, 'pulling this one') $$, (select v from tests.fx where k = 'opinion_post')),
  'an opinion post can still be voided — the escape hatch is kind-agnostic'
);
select is((select status from public.prompt_posts where id = (select v from tests.fx where k = 'opinion_post')),
  'void', 'and voiding it works the same as any other post');

-- ------------------------------------------------------------ non-opinion unaffected --

insert into tests.fx (k, v)
select 'graded_post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 10,
    'options', jsonb_build_array(jsonb_build_object('label', 'Home'), jsonb_build_object('label', 'Away'))
  ))
);

select lives_ok(
  format(
    $$ select prompts.resolve_post(%L, jsonb_build_object(%L, jsonb_build_array((select id::text from public.prompt_slot_options where slot_id = %L and label = 'Home')))) $$,
    (select v from tests.fx where k = 'graded_post'),
    (select id::text from public.prompt_slots where post_id = (select v from tests.fx where k = 'graded_post')),
    (select id from public.prompt_slots where post_id = (select v from tests.fx where k = 'graded_post'))
  ),
  'a non-opinion post still resolves normally after the new guard'
);

select * from finish();
rollback;
