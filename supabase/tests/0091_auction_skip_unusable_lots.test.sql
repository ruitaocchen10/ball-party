-- A card no remaining roster can accept stays hidden. The test sets up two
-- already-filled QB slots directly so it can isolate next-lot selection from
-- bidding mechanics.

begin;
select plan(4);

\ir support/harness.psql

insert into tests.fx (k, v) values ('m', tests.deal(2, 0.41));
select tests.act_as_admin();

-- Pick the earliest QB as the card about to be considered, then give each
-- player a QB slot using different fixture rows. The target QB now has nobody
-- eligible, while later RB/WR/TE cards remain usable.
with target as (
  select min(seq) as seq from public.auction_lots
   where match_id = (select v from tests.fx where k = 'm') and position = 'QB'
), donors as (
  select l.seq, row_number() over (order by l.seq) as n
    from public.auction_lots l, target t
   where l.match_id = (select v from tests.fx where k = 'm') and l.seq <> t.seq
   order by l.seq
   limit 2
), players as (
  select user_id, row_number() over (order by seat) as n
    from public.auction_players
   where match_id = (select v from tests.fx where k = 'm')
)
update public.auction_lots l
   set winner_id = p.user_id, slot = 'QB'
  from donors d join players p using (n)
 where l.match_id = (select v from tests.fx where k = 'm') and l.seq = d.seq;

update public.auction_matches
   set current_lot = (select min(seq) from public.auction_lots
                       where match_id = (select v from tests.fx where k = 'm') and position = 'QB')
 where match_id = (select v from tests.fx where k = 'm');

select ok(
  not exists (
    select 1 from public.auction_players ap
     where ap.match_id = (select v from tests.fx where k = 'm')
       and auction_private.eligible((select v from tests.fx where k = 'm'), ap.user_id,
         (select current_lot from public.auction_matches where match_id = (select v from tests.fx where k = 'm')))
  ),
  'the pending QB cannot be used by anyone'
);

select auction_private.advance((select v from tests.fx where k = 'm'));

select is(
  (select phase from public.auction_matches where match_id = (select v from tests.fx where k = 'm')),
  'lot_preview',
  'the next usable card enters the normal preview phase'
);

select ok(
  (select position <> 'QB' from public.auction_lots l join public.auction_matches am
     on am.match_id = l.match_id and am.current_lot = l.seq
    where l.match_id = (select v from tests.fx where k = 'm')),
  'the unusable QB is skipped in favor of a usable position'
);

select ok(
  (select resolved_at is null from public.auction_lots
    where match_id = (select v from tests.fx where k = 'm')
      and seq = (select min(seq) from public.auction_lots
                  where match_id = (select v from tests.fx where k = 'm') and position = 'QB')),
  'the skipped card is not exposed as a no-sale result'
);

select * from finish();
rollback;
