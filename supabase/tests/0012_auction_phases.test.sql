-- The phase contract is observable through the same public state RPC that a
-- reconnecting client uses.  These are deliberate clock jumps: the server
-- validates every transition under its match-row lock.
begin;
select plan(8);
\ir support/harness.psql

select tests.act_as_admin();
insert into tests.fx (k, v) values ('m', tests.deal(2, 0.77));
update public.matches set status = 'playing', started_at = now() where id = (select v from tests.fx where k = 'm');
select private.auction_advance((select v from tests.fx where k = 'm'));

select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 'lot_preview', 'a new lot begins in the shared preview phase');
select is((select turn_seat from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), null, 'preview has no actionable bidder');
select isnt((select phase_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), null, 'preview publishes a reconnectable deadline');

update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'm');
select private.auction_expire((select v from tests.fx where k = 'm'));
select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 'bidding', 'only the server advances the expired preview into bidding');
select isnt((select turn_deadline from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), null, 'live bidding receives the ten-second deadline');

select tests.act_as(tests.on_clock((select v from tests.fx where k = 'm')));
select public.pass_lot((select v from tests.fx where k = 'm'));
select tests.act_as_admin();
select is((select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 'sold', 'resolution enters sold before exposing another lot');
select is((select current_lot::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 1, 'sold keeps the resolved lot visible');
update public.auction_matches set phase_deadline = now() - interval '1 second' where match_id = (select v from tests.fx where k = 'm');
select private.auction_expire((select v from tests.fx where k = 'm'));
select is((select current_lot::int from public.auction_matches where match_id = (select v from tests.fx where k = 'm')), 2, 'sold expiry advances to the next preview');

select * from finish();
rollback;
