-- Wavelength's cards and targets are secrets with one owner: the psychic for
-- their round. The important assertion is a non-psychic's empty response --
-- not a UI branch -- because PostgREST and Realtime both rely on this RLS
-- boundary.

begin;
select plan(14);

\ir support/harness.psql

create function tests.wl_member(p_match uuid, p_i int) returns uuid
language sql stable security definer as $$
  select rp.user_id
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match
   order by rp.seat
  offset p_i - 1 limit 1;
$$;

create function tests.wl_deal(p_n int, p_mode text, p_preset text, p_seed double precision, out match_id uuid)
returns uuid language plpgsql as $$
begin
  match_id := tests.mkmatch(p_n, 'wavelength_2v2');
  perform tests.act_as_admin();
  perform wavelength_private.deal_board(match_id, p_mode, p_preset, p_seed);
end $$;

insert into tests.fx (k, v) values ('v', tests.wl_deal(4, 'versus', null, 0.25));
select tests.act_as_admin();

insert into tests.fx (k, v)
select 'psychic', psychic_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'v') and round = 1;
insert into tests.fx (k, v)
select 'guesser', guesser_id from public.wavelength_rounds
 where match_id = (select v from tests.fx where k = 'v') and round = 1;
insert into tests.fx (k, v) values ('outsider', tests.mkuser('outsider'));

-- ----------------------------------------------------------- psychic's view --

select tests.act_as((select v from tests.fx where k = 'psychic'));

select is(
  (select count(*)::int from public.wavelength_targets
    where match_id = (select v from tests.fx where k = 'v') and round = 1),
  1,
  'the round psychic can read its target'
);
select is(
  (select count(*)::int from public.wavelength_cards
    where match_id = (select v from tests.fx where k = 'v') and round = 1),
  1,
  'and its card endpoints'
);
select is(
  (select count(*)::int from public.wavelength_targets t
    join public.wavelength_rounds r on r.match_id = t.match_id and r.round = t.round
   where t.match_id = (select v from tests.fx where k = 'v')
     and r.psychic_id <> auth.uid()),
  0,
  'but no target belonging to another psychic'
);
select is(
  (select count(*)::int from public.wavelength_cards c
    join public.wavelength_rounds r on r.match_id = c.match_id and r.round = c.round
   where c.match_id = (select v from tests.fx where k = 'v')
     and r.psychic_id <> auth.uid()),
  0,
  'and no card belonging to another psychic'
);

-- --------------------------------------------------------------- leak check --

select tests.act_as((select v from tests.fx where k = 'guesser'));

select is(
  (select count(*)::int from public.wavelength_targets
    where match_id = (select v from tests.fx where k = 'v') and round = 1),
  0,
  'the guesser receives no target row for their round'
);
select is(
  (select count(*)::int from public.wavelength_cards
    where match_id = (select v from tests.fx where k = 'v') and round = 1),
  0,
  'or card row for their round'
);

select tests.act_as((select v from tests.fx where k = 'outsider'));

select is(
  (select count(*)::int from public.wavelength_targets
    where match_id = (select v from tests.fx where k = 'v')),
  0,
  'a non-participant receives no targets'
);
select is(
  (select count(*)::int from public.wavelength_cards
    where match_id = (select v from tests.fx where k = 'v')),
  0,
  'and no cards'
);
select throws_ok(
  $$ select count(*) from wavelength_private.deck $$,
  '42501', 'permission denied for schema wavelength_private',
  'the deck remains unreachable to a client'
);

select tests.act_as_admin();

select ok(
  has_table_privilege('authenticated', 'public.wavelength_cards', 'select'),
  'authenticated players have the table privilege RLS needs for cards'
);
select ok(
  has_table_privilege('authenticated', 'public.wavelength_targets', 'select'),
  'authenticated players have the table privilege RLS needs for targets'
);
select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename in ('wavelength_cards', 'wavelength_targets')),
  0,
  'neither hidden table is in the Realtime publication'
);
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public'
      and tablename in ('wavelength_cards', 'wavelength_targets')
      and policyname in ('wavelength_cards_select_psychic', 'wavelength_targets_select_psychic')),
  2,
  'both hidden tables have exactly their psychic-only policy'
);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'anon', true);
select is(
  (select count(*)::int from (
     select match_id from public.wavelength_cards
     union all
     select match_id from public.wavelength_targets
   ) hidden),
  0,
  'an anonymous session receives no rows from either hidden table'
);

select * from finish();
rollback;
