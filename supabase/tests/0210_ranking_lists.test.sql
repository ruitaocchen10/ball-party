-- Tests for 0210-0212: versioned ranking lists, their edit rules, the
-- friends-only update card, prompt answers feeding lists, and the backfill.

begin;
select plan(50);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('admin', tests.mkuser('admin'));
insert into tests.fx (k, v) values ('alice', tests.mkuser('alice'));
insert into tests.fx (k, v) values ('bob',   tests.mkuser('bob'));
insert into tests.fx (k, v) values ('carol', tests.mkuser('carol'));
insert into tests.fx (k, v) values ('eve',   tests.mkuser('eve'));
insert into tests.fx (k, v) values ('guest', tests.mkguest('guest'));

-- alice and bob are friends; carol is a stranger to both.
insert into public.friendships (requester_id, addressee_id, status)
values ((select v from tests.fx where k = 'alice'), (select v from tests.fx where k = 'bob'), 'accepted');

insert into prompts_private.admin_config (email)
select email from auth.users where id = (select v from tests.fx where k = 'admin');

-- Six QBs and a WR in the player directory.
insert into prompts_private.nfl_players (player_id, display_name, search_name, position, team, status, season)
select 'TQB' || i, 'QB ' || i, 'qb ' || i, 'QB', 'KC', 'ACT', 2026 from generate_series(1, 12) i;
insert into prompts_private.nfl_players (player_id, display_name, search_name, position, team, status, season)
values ('TWR1', 'WR 1', 'wr 1', 'WR', 'KC', 'ACT', 2026);

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

create function tests.id(p text) returns uuid
language sql stable as $$ select v from tests.fx where k = p $$;

create function tests.act_as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
end $$;

-- The first n team codes, and the same n reversed (a different order).
create function tests.teams(p_n int) returns text[]
language sql security definer as $$ select (private.nfl_team_codes())[1:p_n] $$;

create function tests.teams_rev(p_n int) returns text[]
language sql security definer as $$
  select array(select c from unnest((private.nfl_team_codes())[1:p_n]) with ordinality t(c, o) order by o desc)
$$;

create function tests.power_slots() returns jsonb
language sql security definer as $$
  select jsonb_build_array(jsonb_build_object(
    'label', 'NFL Power Rankings', 'shape', 'rank', 'pick_count', 32, 'points', 1,
    'options', (select jsonb_agg(jsonb_build_object('label', c, 'team_code', c, 'sort_order', o))
                  from unnest(private.nfl_team_codes()) with ordinality t(c, o))
  ));
$$;

create function tests.option_ids(p_post uuid, p_codes text[]) returns uuid[]
language sql security definer as $$
  select array_agg(o.id order by u.ord)
    from unnest(p_codes) with ordinality u(code, ord)
    join public.prompt_slots s on s.post_id = p_post
    join public.prompt_slot_options o on o.slot_id = s.id and o.team_code = u.code
$$;

create function tests.choices(p_post uuid, p_codes text[]) returns jsonb
language sql security definer as $$
  select jsonb_build_object(
    (select id::text from public.prompt_slots where post_id = p_post),
    to_jsonb(tests.option_ids(p_post, p_codes)))
$$;

-- The caller's current list for a kind, as ordered team codes / player ids.
create function tests.cur_items(p_kind text) returns text[]
language sql stable as $$
  select array_agg(coalesce(i.team_code, i.player_id) order by i.place)
    from public.ranking_lists l
    join public.ranking_list_items i on i.version_id = l.current_version_id
   where l.profile_id = auth.uid() and l.kind = p_kind
$$;

create function tests.uname(p text) returns text
language sql security definer as $$
  select username from public.profiles where id = tests.id(p)
$$;

-- Moves a power rankings version back in time, as the owner.
create function tests.age_version(p_who text, p_no int, p_age interval) returns void
language sql security definer as $$
  update public.ranking_list_versions v set created_at = now() - p_age
    from public.ranking_lists l
   where l.id = v.list_id and l.profile_id = tests.id(p_who) and l.kind = 'power_rankings' and v.version_no = p_no
$$;

-- An open Power Rankings prompt.
select tests.act_as_prompts_admin();
insert into tests.fx (k, v)
select 'post', prompts.create_post(
  'power_rankings', 'Power rankings', 'cap', 'rank the league', 'crit',
  now() + interval '1 day', tests.power_slots(), null::jsonb, true,
  array['ARI', 'ATL', 'BAL', 'BUF', 'CAR', 'CHI']
);

-- --------------------------------------------- an open prompt owns the list --

select tests.act_as(tests.id('alice'));
select throws_ok(
  $$ select public.save_ranking_list('power_rankings', tests.teams(10)) $$,
  '55000', 'prompt_open', 'a standalone save is refused while a prompt for the kind is open');

-- ------------------------------------------- a prompt answer saves a version --

select prompts.submit_response(tests.id('post'), tests.choices(tests.id('post'), tests.teams_rev(5)));

select is(
  (select count(*)::int from public.ranking_list_versions v join public.ranking_lists l on l.id = v.list_id
    where l.profile_id = tests.id('alice') and l.kind = 'power_rankings'),
  1, 'answering the prompt leaves exactly one list version');

select ok(
  exists (select 1 from public.ranking_list_versions v join public.ranking_lists l on l.id = v.list_id
           where l.profile_id = tests.id('alice') and v.source = 'prompt' and v.post_id = tests.id('post')
             and v.id = l.current_version_id),
  'it is a prompt version tied to the post, and it is current');

select is(tests.cur_items('power_rankings'), tests.teams_rev(5), 'its items are the answer, in the order chosen');

-- Resubmitting while the prompt is open overwrites the same version.
select prompts.submit_response(tests.id('post'), tests.choices(tests.id('post'), tests.teams(5)));

select is(
  (select count(*)::int from public.ranking_list_versions v join public.ranking_lists l on l.id = v.list_id
    where l.profile_id = tests.id('alice') and l.kind = 'power_rankings'),
  1, 'resubmitting an open prompt does not add a version');

select is(tests.cur_items('power_rankings'), tests.teams(5), 'it overwrites the items');

-- -------------------------------------------------------------- edit rules --

-- Locked by time, status left open, exactly as production has it. This also
-- closes the open Power Rankings prompt the seed data carries.
select tests.act_as_admin();
update public.prompt_posts set lock_at = now() - interval '1 hour'
 where ranking_kind = 'power_rankings' and lock_at > now();
select tests.act_as(tests.id('alice'));

select public.save_ranking_list('power_rankings', tests.teams(10));

select is(
  (select max(v.version_no)::int from public.ranking_list_versions v join public.ranking_lists l on l.id = v.list_id
    where l.profile_id = tests.id('alice') and l.kind = 'power_rankings'),
  2, 'once the prompt has locked, a save is a new version (prompt versions do not count toward the cap)');

select throws_ok(
  $$ select public.save_ranking_list('power_rankings', tests.teams(10)) $$,
  '22023', 'no_change', 'saving the list as it already is is refused');

-- Inside the typo-grace window the save replaces the version.
select public.save_ranking_list('power_rankings', tests.teams_rev(10));

select is(
  (select count(*)::int from public.ranking_list_versions v join public.ranking_lists l on l.id = v.list_id
    where l.profile_id = tests.id('alice') and l.kind = 'power_rankings'),
  2, 'a save within 10 minutes of the last edit replaces it instead of adding a version');

select is(tests.cur_items('power_rankings'), tests.teams_rev(10), 'the replaced version holds the new items');

select tests.act_as_admin();
select tests.age_version('alice', 2, interval '11 minutes');
select tests.act_as(tests.id('alice'));

select throws_ok(
  $$ select public.save_ranking_list('power_rankings', tests.teams(10)) $$,
  '55000', 'edit_limit', 'past the grace window a second edit inside 24 hours is refused');

select tests.act_as_admin();
select tests.age_version('alice', 2, interval '25 hours');
select tests.act_as(tests.id('alice'));

select public.save_ranking_list('power_rankings', tests.teams(10));

select is(
  (select max(v.version_no)::int from public.ranking_list_versions v join public.ranking_lists l on l.id = v.list_id
    where l.profile_id = tests.id('alice') and l.kind = 'power_rankings'),
  3, 'after 24 hours the next edit is a new version');

-- ------------------------------------------------------------ update card --

select tests.act_as_admin();
select tests.age_version('alice', 3, interval '25 hours');
select tests.act_as(tests.id('alice'));

select public.save_ranking_list('power_rankings', tests.teams_rev(32), 'Chiefs are back', true);

select is(
  (select count(*)::int from public.prompt_posts
    where template_kind = 'ranking_update' and author_id = tests.id('alice')),
  1, 'publishing creates one update card');

select ok(
  exists (select 1 from public.prompt_posts
           where template_kind = 'ranking_update' and author_id = tests.id('alice')
             and status = 'locked' and is_opinion and ranking_kind = 'power_rankings'
             and template_name = 'Power Rankings update'),
  'the card is a locked, ungraded Power Rankings update');

select is(
  (select body from public.prompt_comments c join public.prompt_posts p on p.id = c.post_id
    where p.template_kind = 'ranking_update' and c.parent_comment_id is null and c.posted_with_pick
      and c.author_id = tests.id('alice')),
  'Chiefs are back', 'the note is the take the replies hang on');

select ok(
  exists (select 1 from public.ranking_list_versions v join public.ranking_lists l on l.id = v.list_id
           where l.profile_id = tests.id('alice') and v.version_no = 4 and v.update_post_id is not null),
  'the version points at its card');

-- ---------------------------------------------------------- friends only --

select tests.act_as(tests.id('bob'));
select is((select count(*)::int from public.prompt_posts where template_kind = 'ranking_update'), 1,
  'a friend can see the update card');
select is((select count(*)::int from public.prompt_comments c join public.prompt_posts p on p.id = c.post_id
            where p.template_kind = 'ranking_update'), 1, 'and its take');

select is((select count(*)::int from public.friend_list_updates()), 1, 'a friend''s home feed lists the update');
select ok((select prev_items is not null and cardinality(items) = 32 and note = 'Chiefs are back' and kind = 'power_rankings'
             from public.friend_list_updates()), 'with the list, the list it replaced and the note');

select tests.act_as(tests.id('carol'));
select is((select count(*)::int from public.friend_list_updates()), 0, 'a stranger''s home feed lists no update');
select is((select count(*)::int from public.prompt_posts where template_kind = 'ranking_update'), 0,
  'a stranger cannot see the update card');
select is((select count(*)::int from public.prompt_comments c
            where c.author_id = tests.id('alice') and c.posted_with_pick and c.body = 'Chiefs are back'), 0,
  'or its take');

select tests.act_as_anon();
select is((select count(*)::int from public.prompt_posts where template_kind = 'ranking_update'), 0,
  'a signed-out visitor cannot see the update card');

select tests.act_as_admin();
insert into tests.fx (k, v)
select 'take', c.id from public.prompt_comments c join public.prompt_posts p on p.id = c.post_id
 where p.template_kind = 'ranking_update' and c.parent_comment_id is null;
insert into tests.fx (k, v)
select 'card', id from public.prompt_posts where template_kind = 'ranking_update';

select tests.act_as(tests.id('bob'));
select lives_ok(
  $$ select prompts.post_comment(tests.id('card'), 'No way', tests.id('take')) $$,
  'a friend can reply to the update card');

select tests.act_as(tests.id('carol'));
select throws_ok(
  $$ select prompts.post_comment(tests.id('card'), 'Hi', tests.id('take')) $$,
  'P0002', 'post_not_found', 'a stranger cannot reply to it');

-- A reply stops the typo-grace replace, so the daily cap applies.
select tests.act_as(tests.id('alice'));
select throws_ok(
  $$ select public.save_ranking_list('power_rankings', tests.teams(5)) $$,
  '55000', 'edit_limit', 'a card with a reply cannot be replaced inside the grace window');

-- ----------------------------------------------------------------- reads --

select tests.act_as(tests.id('bob'));
select is(
  (select note from public.get_ranking_list(tests.uname('alice'), 'power_rankings') where version_no = 4),
  'Chiefs are back', 'a friend sees the note in the history');

select is(
  (select note from public.get_ranking_lists(tests.uname('alice')) where kind = 'power_rankings'),
  'Chiefs are back', 'a friend sees the latest note on the list summary');

select ok(
  (select prev_items is not null and prev_items <> items from public.get_ranking_lists(tests.uname('alice')) where kind = 'power_rankings'),
  'the summary carries the version it replaced, so the card can show movement');

select tests.act_as(tests.id('carol'));
select is(
  (select note from public.get_ranking_lists(tests.uname('alice')) where kind = 'power_rankings'),
  null, 'a stranger sees no note on the list summary');
select is(
  (select count(*)::int from public.get_ranking_list(tests.uname('alice'), 'power_rankings')
    where note is not null or update_post_id is not null),
  0, 'a stranger sees the history without notes or cards');
select is(
  (select version_count from public.get_ranking_lists(tests.uname('alice')) where kind = 'power_rankings'),
  4, 'and the list summary with its version count');

select tests.act_as(tests.id('alice'));
select is((select count(*)::int from public.ranking_list_prefill(tests.id('post'))), 32,
  'the prompt prefill maps every item onto the prompt''s options');
select is(
  (select o.team_code from public.ranking_list_prefill(tests.id('post')) f
     join public.prompt_slot_options o on o.id = f.option_id order by f.place limit 1),
  'WAS', 'in list order');

-- Private profile: the stranger is shut out, the friend is not.
select tests.act_as_admin();
update public.profiles set is_private = true where id = tests.id('alice');

select tests.act_as(tests.id('carol'));
select is((select count(*)::int from public.get_ranking_lists(tests.uname('alice'))), 0,
  'a private profile''s lists are hidden from a stranger');
select tests.act_as(tests.id('bob'));
select is((select count(*)::int from public.get_ranking_lists(tests.uname('alice'))), 1,
  'but not from a friend');

-- ----------------------------------------------------------------- access --

select tests.act_as_guest(tests.id('guest'));
select throws_ok(
  $$ select public.save_ranking_list('power_rankings', tests.teams(5)) $$,
  '42501', 'not_authenticated', 'a guest cannot save a list');

select tests.act_as(tests.id('alice'));
select throws_ok(
  $$ insert into public.ranking_lists (profile_id, kind) values (auth.uid(), 'qb') $$,
  '42501', null, 'the tables take no direct writes');

select tests.act_as(tests.id('bob'));
select is((select count(*)::int from public.ranking_lists), 0, 'a player reads only their own rows of the tables');

-- ---------------------------------------------------------- position lists --

select tests.act_as(tests.id('alice'));
select public.save_ranking_list('qb', array['TQB3', 'TQB1', 'TQB2', 'TQB5', 'TQB4', 'TQB6', 'TQB7', 'TQB8', 'TQB9', 'TQB10']);
select is(tests.cur_items('qb'), array['TQB3', 'TQB1', 'TQB2', 'TQB5', 'TQB4', 'TQB6', 'TQB7', 'TQB8', 'TQB9', 'TQB10'], 'a position list saves its players in order');

select throws_ok(
  $$ select public.save_ranking_list('qb', array['TQB1', 'TQB2', 'TQB3', 'TQB4', 'TQB5', 'TQB6', 'TQB7', 'TQB8', 'TQB9', 'TWR1']) $$,
  '22023', 'invalid_ranking_items', 'a player of another position is refused');

-- ------------------------------------------------------------- validation --

select throws_ok(
  $$ select public.save_ranking_list('power_rankings', tests.teams(7)) $$,
  '22023', 'invalid_ranking_size', 'a length the kind does not allow is refused');
select throws_ok(
  $$ select public.save_ranking_list('qb', array['TQB1', 'TQB1', 'TQB2', 'TQB3', 'TQB4', 'TQB5', 'TQB6', 'TQB7', 'TQB8', 'TQB9']) $$,
  '22023', 'invalid_ranking_items', 'a repeated item is refused');
select throws_ok(
  $$ select public.save_ranking_list('power_rankings', array['ARI', 'ATL', 'BAL', 'BUF', 'ZZZ']) $$,
  '22023', 'invalid_ranking_items', 'a team that does not exist is refused');

-- ---------------------------------------------------------------- backfill --

-- A response written before lists existed has no version.
select tests.act_as_admin();
insert into public.prompt_responses (post_id, slot_id, profile_id, chosen_option_ids)
select tests.id('post'), (select id from public.prompt_slots where post_id = tests.id('post')),
       tests.id('eve'), tests.option_ids(tests.id('post'), tests.teams_rev(5));

select cmp_ok(private.ranking_backfill_power_rankings(), '>=', 1, 'the backfill adds a version for the response that has none');

select tests.act_as(tests.id('eve'));
select is(tests.cur_items('power_rankings'), tests.teams_rev(5), 'it holds the response''s ranking, in order');

select tests.act_as_admin();
select is(private.ranking_backfill_power_rankings(), 0, 'a second run adds nothing');

-- The Rams are LAR, so they cannot be confused with the Chargers (LAC).
select ok('LAR' = any (private.nfl_team_codes()) and not ('LA' = any (private.nfl_team_codes())),
  'lists accept LAR, not LA');

-- ------------------------------------------------------------ player names --

select tests.act_as(tests.id('alice'));
select is((select array_agg(display_name order by player_id) from public.ranking_players(array['TQB1', 'TQB2', 'NOPE'])),
          array['QB 1', 'QB 2'], 'ranking_players names the players asked about and skips unknown ids');

select * from finish();
rollback;
