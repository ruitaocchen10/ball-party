-- Tests for Weekly Awards (0175): create_post accepts exactly the six-slot
-- opinion shape, submit_response creates a player's option the first time
-- anyone picks them in a slot (and only once), validates the player against
-- the directory, and post_aggregates works over the lazily created options.

begin;
select plan(17);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values
  ('admin', tests.mkuser('admin')),
  ('alice', tests.mkuser('alice')),
  ('bob', tests.mkuser('bob'));
insert into tests.fx (k, v) select 'guest', tests.mkguest('guest');

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

-- The six slots the composer builds. p_player_search lets a test break the shape.
create function tests.awards_slots(p_player_search boolean default true) returns jsonb
language sql as $$
  with teams as (
    select jsonb_agg(jsonb_build_object('label', code, 'team_code', code, 'sort_order', n - 1) order by n) as options
      from unnest(array['ARI','ATL','BAL','BUF','CAR','CHI','CIN','CLE','DAL','DEN','DET','GB','HOU','IND','JAX','KC',
                        'LA','LAC','LV','MIA','MIN','NE','NO','NYG','NYJ','PHI','PIT','SEA','SF','TB','TEN','WAS'])
           with ordinality as t(code, n)
  )
  select jsonb_build_array(
    jsonb_build_object('label', 'Biggest winner', 'shape', 'pick', 'points', 1, 'options', (select options from teams)),
    jsonb_build_object('label', 'Biggest loser', 'shape', 'pick', 'points', 1, 'options', (select options from teams)),
    jsonb_build_object('label', 'Best game', 'shape', 'pick', 'points', 1,
      'options', jsonb_build_array(jsonb_build_object('label', 'KC @ BUF', 'sublabel', 'Sun', 'sort_order', 0))),
    jsonb_build_object('label', 'Offensive player of the week', 'shape', 'pick', 'points', 1, 'player_search', p_player_search),
    jsonb_build_object('label', 'Defensive player of the week', 'shape', 'pick', 'points', 1, 'player_search', true),
    jsonb_build_object('label', 'LVP', 'shape', 'pick', 'points', 1, 'player_search', true)
  );
$$;

-- A complete answer: slot label -> chosen option (team code, matchup label, or player id).
create function tests.awards_choices(p_post uuid, p_winner text, p_loser text, p_off text, p_def text, p_lvp text)
returns jsonb language sql security definer as $$
  select jsonb_object_agg(s.id::text, jsonb_build_array(
    case s.label
      when 'Biggest winner' then (select o.id::text from public.prompt_slot_options o where o.slot_id = s.id and o.team_code = p_winner)
      when 'Biggest loser'  then (select o.id::text from public.prompt_slot_options o where o.slot_id = s.id and o.team_code = p_loser)
      when 'Best game'      then (select o.id::text from public.prompt_slot_options o where o.slot_id = s.id limit 1)
      when 'Offensive player of the week' then p_off
      when 'Defensive player of the week' then p_def
      else p_lvp
    end))
  from public.prompt_slots s where s.post_id = p_post;
$$;

select prompts_private.sync_nfl_players(
  'season,team,position,status,full_name,gsis_id,headshot_url' || E'\n' ||
  '2026,KC,QB,ACT,Patrick Mahomes,00-0033873,"https://img/mahomes.png"' || E'\n' ||
  '2026,SF,DL,ACT,Nick Bosa,00-0035710,"https://img/bosa.png"' || E'\n' ||
  '2026,LA,K,ACT,Joshua Karty,00-0038001,');

-- ------------------------------------------------------------- create_post --

select tests.act_as_prompts_admin();

insert into tests.fx (k, v)
select 'post', prompts.create_post('weekly_awards', 'Weekly Awards', 'cap', 'Week 5 awards', 'Opinion only',
  now() + interval '1 day', tests.awards_slots(), null::jsonb, true);

select is((select count(*)::int from public.prompt_slots where post_id = (select v from tests.fx where k = 'post')),
  6, 'an admin can create a Weekly Awards post with six slots');

select is((select array_agg(player_search order by sort_order) from public.prompt_slots where post_id = (select v from tests.fx where k = 'post')),
  array[false, false, false, true, true, true], 'the last three slots are open player searches');

select is((select count(*)::int from public.prompt_slot_options o join public.prompt_slots s on s.id = o.slot_id
            where s.post_id = (select v from tests.fx where k = 'post') and s.player_search),
  0, 'player slots start with no options');

select throws_ok(
  $$ select prompts.create_post('weekly_awards', 'Weekly Awards', 'c', 't', 'r', now() + interval '1 day', tests.awards_slots(), null::jsonb, false) $$,
  'invalid_weekly_awards', 'a Weekly Awards post that is not an opinion post is refused');

select throws_ok(
  $$ select prompts.create_post('weekly_awards', 'Weekly Awards', 'c', 't', 'r', now() + interval '1 day', tests.awards_slots(false), null::jsonb, true) $$,
  'invalid_weekly_awards', 'the offensive-player slot must be a player search');

select throws_ok(
  $$ select prompts.create_post('weekly_awards', 'Weekly Awards', 'c', 't', 'r', now() + interval '1 day', (tests.awards_slots()) - 5, null::jsonb, true) $$,
  'invalid_weekly_awards', 'a Weekly Awards post needs all six slots');

select throws_ok(
  $$ select prompts.create_post('custom_multi', 'Other', 'c', 't', 'r', now() + interval '1 day', tests.awards_slots(), null::jsonb, true) $$,
  'invalid_weekly_awards', 'only Weekly Awards may carry player-search slots');

select throws_ok(
  format($$ select prompts.resolve_post(%L, '{}'::jsonb) $$, (select v from tests.fx where k = 'post')),
  'opinion_not_resolvable', 'a Weekly Awards post can never be graded');

-- --------------------------------------------------------- submit_response --

select tests.act_as((select v from tests.fx where k = 'alice'));

select throws_ok(
  format($$ select prompts.submit_response(%L, tests.awards_choices(%L, 'KC', 'NYJ', '00-0033873', '00-0035710', 'nobody')) $$,
    (select v from tests.fx where k = 'post'), (select v from tests.fx where k = 'post')),
  'invalid_option', 'a player id that is not in the directory is refused');

select throws_ok(
  format($$ select prompts.submit_response(%L, tests.awards_choices(%L, 'KC', 'NYJ', '00-0033873', '00-0035710', 'nobody') - (select id::text from public.prompt_slots where post_id = %L and label = 'LVP')) $$,
    (select v from tests.fx where k = 'post'), (select v from tests.fx where k = 'post'), (select v from tests.fx where k = 'post')),
  'incomplete_slot', 'every one of the six slots is required');

select lives_ok(
  format($$ select prompts.submit_response(%L, tests.awards_choices(%L, 'KC', 'NYJ', '00-0033873', '00-0035710', '00-0038001')) $$,
    (select v from tests.fx where k = 'post'), (select v from tests.fx where k = 'post')),
  'a signed-in user can answer all six slots');

select tests.act_as((select v from tests.fx where k = 'bob'));
select lives_ok(
  format($$ select prompts.submit_response(%L, tests.awards_choices(%L, 'KC', 'BAL', '00-0033873', '00-0038001', '00-0038001')) $$,
    (select v from tests.fx where k = 'post'), (select v from tests.fx where k = 'post')),
  'a second user can pick the same player');

select tests.act_as_admin();

select is((select count(*)::int from public.prompt_slot_options o join public.prompt_slots s on s.id = o.slot_id
            where s.post_id = (select v from tests.fx where k = 'post') and s.label = 'Offensive player of the week'),
  1, 'two users picking the same player share one option row');

select is((select o.label || '|' || o.sublabel || '|' || o.team_code from public.prompt_slot_options o join public.prompt_slots s on s.id = o.slot_id
            where s.post_id = (select v from tests.fx where k = 'post') and s.label = 'Offensive player of the week'),
  'Patrick Mahomes|QB · KC|KC', 'the option carries the directory name, position and team');

select throws_ok(
  format($$ insert into public.prompt_slot_options (slot_id, label, player_id)
            select id, 'Dup', '00-0033873' from public.prompt_slots where post_id = %L and label = 'Offensive player of the week' $$,
    (select v from tests.fx where k = 'post')),
  '23505', null, 'the database refuses a second option for the same player in a slot');

select is(
  (select pct from prompts.post_aggregates((select v from tests.fx where k = 'post')) a
     join public.prompt_slot_options o on o.id = a.option_id
    where o.player_id = '00-0035710'),
  50::numeric, 'aggregates cover lazily created player options (one of two picked Bosa)');

select tests.act_as_guest((select v from tests.fx where k = 'guest'));
select throws_ok(
  format($$ select prompts.submit_response(%L, '{}'::jsonb) $$, (select v from tests.fx where k = 'post')),
  'not_authenticated', 'a guest cannot answer');

select * from finish();
rollback;
