begin;
select plan(6);
\ir support/harness.psql

create function tests.preset_stranding_report() returns text[] language plpgsql as $$
declare v_n int; v_preset text; v_strategy text; v_seed int; v_match uuid; v_bad text[] := '{}';
begin
  foreach v_preset in array array['standard', 'full', 'deep'] loop
    foreach v_n in array array[2, 3, 4] loop
      foreach v_strategy in array array['pass', 'raise', 'random'] loop
        for v_seed in 1 .. 3 loop
          v_match := tests.deal_and_open(v_n, v_seed * 0.17, v_preset);
          perform tests.play_out(v_match, v_strategy, v_seed); perform tests.act_as_admin();
          if tests.stranded(v_match) <> '{}'::text[] then v_bad := v_bad || format('%s N=%s %s seed=%s %s', v_preset, v_n, v_strategy, v_seed, tests.stranded(v_match)); end if;
          if (select status from public.matches where id = v_match) <> 'complete' then v_bad := v_bad || format('%s N=%s %s seed=%s incomplete', v_preset, v_n, v_strategy, v_seed); end if;
        end loop;
      end loop;
    end loop;
  end loop;
  return v_bad;
end $$;

select tests.mkmatch(4) as standard_match \gset
select public.start_auction(:'standard_match', 'weekly', 'standard');
select is((select row(qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, lot_count)::text from public.auction_matches where match_id = :'standard_match'), '(1,1,1,1,1,25,20)', 'standard resolves to five slots, $25, and 20 lots');

select tests.mkmatch(4) as full_match \gset
select public.start_auction(:'full_match', 'weekly', 'full');
select is((select row(qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, lot_count)::text from public.auction_matches where match_id = :'full_match'), '(1,2,2,1,1,35,28)', 'full resolves to seven slots, $35, and 28 lots');

select tests.mkmatch(4) as deep_match \gset
select public.start_auction(:'deep_match', 'weekly', 'deep');
select is((select row(qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, lot_count)::text from public.auction_matches where match_id = :'deep_match'), '(2,2,3,1,2,50,40)', 'deep resolves to ten slots, $50, and 40 lots');
select is((select array_agg(distinct budget order by budget) from public.auction_players where match_id = :'deep_match'), array[50], 'the resolved deep purse is given to every player');

select tests.act_as_admin();
select ok(private.auction_eligible(:'deep_match', (select user_id from public.auction_players where match_id = :'deep_match' limit 1), 1::smallint), 'a deep-board player is eligible before either quarterback slot is filled');
select is(tests.preset_stranding_report(), '{}'::text[], 'every preset, table size, bidding strategy, and seed completes with every slot exactly filled');
select * from finish();
rollback;
