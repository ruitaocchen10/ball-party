-- Tests for push_info reading a game pick's game from its slot (0221): the
-- matchup, kickoff, week and points reach the alert copy.

begin;
select plan(5);
\ir support/harness.psql

insert into tests.fx (k, v) values
  ('admin', tests.mkuser('PiAdmin')),
  ('alice', tests.mkuser('PiAlice'));

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

create function tests.lookup_email(p_id uuid) returns text
language sql security definer as $$ select email from auth.users where id = p_id; $$;

create function tests.act_as_prompts_admin() returns void
language plpgsql as $$
declare v_id uuid := (select v from tests.fx where k = 'admin');
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_id::text, 'role', 'authenticated', 'is_anonymous', false, 'email', tests.lookup_email(v_id))::text,
    true);
  perform set_config('role', 'authenticated', true);
end $$;

create function tests.who(p_k text) returns uuid language sql stable as $$ select v from tests.fx where k = p_k $$;

insert into public.nfl_games (id, season, week, kickoff, away_team, home_team)
values ('2026_06_ZZ_YY', 2026, 6, now() + interval '2 days', 'ZZ', 'YY');

select tests.act_as(tests.who('alice'));
select public.register_device_token(repeat('a', 64), 'sandbox');

select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'game_pick', 'Game pick', 'cap', 'who wins', 'crit', now() + interval '1 day',
  jsonb_build_array(jsonb_build_object(
    'label', 'Winner', 'shape', 'pick', 'points', 20, 'source_game_id', '2026_06_ZZ_YY',
    'options', jsonb_build_array(jsonb_build_object('label', 'YY'), jsonb_build_object('label', 'ZZ'))
  ))
);

select tests.act_as_admin();
create temp table info on commit drop as
select private.push_info(o) as j from public.push_outbox o
 where o.kind = 'new_prompt' and o.post_id = tests.who('post') and o.recipient_id = tests.who('alice');

select is((select j ->> 'template_kind' from info), 'game_pick', 'push info carries the prompt kind');
select is((select j ->> 'away_team' from info) || ' @ ' || (select j ->> 'home_team' from info), 'ZZ @ YY',
  'and the matchup, found through the slot');
select ok((select j ? 'kickoff' from info), 'and the kickoff');
select is((select (j ->> 'week')::int from info), 6, 'and the game''s own week');
select is((select (j ->> 'points')::int from info), 20, 'and the points');

select * from finish();
rollback;
