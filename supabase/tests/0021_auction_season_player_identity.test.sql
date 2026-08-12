begin;
select plan(3);

\ir support/harness.psql

-- One board, one player. A single board is a weak test of that rule: under the
-- player-season identity this replaces, roughly half of standard boards still
-- came out clean by luck, which is why the bug survived a suite that asserted
-- uniqueness on exactly the key the dealer was using. The sweep is what makes
-- the failure reproducible rather than seed-dependent.
create function tests.season_repeat_report() returns text[] language plpgsql as $$
declare v_preset text; v_seed int; v_match uuid; v_repeat text; v_bad text[] := '{}';
begin
  foreach v_preset in array array['standard', 'full', 'deep'] loop
    for v_seed in 1 .. 10 loop
      v_match := tests.deal(4, v_seed * 0.0231, 'season_total', v_preset);
      perform tests.act_as_admin();
      select string_agg(display_name || ' ' || seasons, ', ') into v_repeat from (
        select display_name, string_agg(season::text, '/' order by season) as seasons
          from public.auction_lots
         where match_id = v_match
         group by player_id, display_name
        having count(*) > 1
      ) repeated;
      if v_repeat is not null then
        v_bad := v_bad || format('%s seed=%s %s', v_preset, v_seed, v_repeat);
      end if;
    end loop;
  end loop;
  return v_bad;
end $$;

select is(
  tests.season_repeat_report(),
  '{}'::text[],
  'no season board in any preset offers the same player in two different seasons'
);

-- The identity rule tightened, so the pool it draws against got shallower: the
-- season pool holds 2,704 rows but only 810 people. The deepest board is the
-- one that would strand first if that depth were not enough.
select tests.deal(4, 0.41, 'season_total', 'deep') as deep_season \gset
select tests.act_as_admin();
select is(
  (select count(distinct player_id)::int from public.auction_lots where match_id = :'deep_season'),
  40,
  'the deepest season board still fills forty lots with forty distinct people'
);

select tests.deal(4, 0.41, 'weekly', 'deep') as deep_weekly \gset
select tests.act_as_admin();
select is(
  (select count(distinct player_id)::int from public.auction_lots where match_id = :'deep_weekly'),
  40,
  'weekly boards keep the player-level identity they already had'
);

select * from finish();
rollback;
