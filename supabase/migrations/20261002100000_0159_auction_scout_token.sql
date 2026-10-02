-- Scout token: a second single-use ability from the same budget 0158 added.
-- Spending it on the lot currently showing reveals a coarse, position-relative
-- performance tier -- "rough"/"solid"/"great" -- to the spending player only,
-- before the lot resolves. Nobody else, including the opponent, ever
-- receives that row: not through a screen, not through the realtime socket.
--
-- The direct precedent is `public.sabotage_draft_picks` (0052): a bare
-- `user_id = auth.uid()` SELECT policy on a table that sits in the
-- `supabase_realtime` publication is what keeps a value scoped to its owner
-- even over the websocket, not merely hidden by the UI. The auction's own
-- existing hidden-value mechanism -- `private.auction_answers`, kept out of
-- the publication entirely and revealed to everyone at once by `resolve()`
-- copying it onto the public row -- is a different shape (hidden from
-- everyone until a shared reveal) and is the wrong thing to copy here.
--
-- Deliberately out of scope for this slice: season-total matches. The tier
-- breakpoints below are week-relative PPR thresholds -- the same ones
-- `weeklyRevealTier` in webapp/lib/games/auction/board.ts already uses for
-- the post-sale reveal -- and a season total has no equivalent yet (see that
-- function's own doc comment: it needs a server-calculated percentile, not a
-- single-number guess). `use_scout_token` refuses outright on a season-mode
-- match rather than ship a tier that means something different than it says.

-- ------------------------------------------------------------------- table --

create table public.auction_scouting_hints (
  match_id   uuid        not null,
  seq        smallint    not null,
  user_id    uuid        not null references public.profiles (id),
  tier       text        not null check (tier in ('rough', 'solid', 'great')),
  created_at timestamptz not null default now(),
  primary key (match_id, seq, user_id),
  foreign key (match_id, seq) references public.auction_lots (match_id, seq) on delete cascade
);

alter table public.auction_scouting_hints enable row level security;

-- The one policy that matters: nobody but the row's own owner can select it,
-- which Realtime enforces at the wire the same way it does for
-- sabotage_draft_picks -- a dropped/replayed payload can never hand this to
-- the wrong viewer because the server never sends it to them in the first
-- place.
create policy auction_scouting_hints_select_own on public.auction_scouting_hints
  for select to authenticated using (user_id = auth.uid());

-- No insert/update/delete policy -- written only by auction.use_scout_token
-- below, the same shape every other auction write already has.

alter publication supabase_realtime add table public.auction_scouting_hints;

-- ------------------------------------------------------------------ tiering --

-- Mirrors webapp/lib/games/auction/board.ts's weeklyRevealTier() breakpoints
-- exactly -- QB 15/25, TE 8/16, RB/WR/FLEX 10/20 PPR. If one side's
-- thresholds ever move, the other has to move with it; nothing enforces that
-- but this comment and the matching one on weeklyRevealTier.
create function auction_private.weekly_tier(p_position text, p_points numeric)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select case
    when p_position = 'QB' then case when p_points < 15 then 'rough' when p_points >= 25 then 'great' else 'solid' end
    when p_position = 'TE' then case when p_points < 8  then 'rough' when p_points >= 16 then 'great' else 'solid' end
    else                         case when p_points < 10 then 'rough' when p_points >= 20 then 'great' else 'solid' end
  end;
$function$;

-- --------------------------------------------------------------------- RPC --

create function auction.use_scout_token(p_match_id uuid)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user       uuid := auth.uid();
  v_status     public.match_status;
  v_board      public.auction_matches;
  v_used_scout boolean;
  v_position   text;
  v_points     numeric(5,1);
  v_tier       text;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  select status into v_status from public.matches where id = p_match_id;
  if v_status is distinct from 'playing'::public.match_status then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  select * into v_board from public.auction_matches where match_id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  -- The points a tier would be computed from are already public once a lot
  -- is sold -- scouting one at that point would just restate what the lot
  -- card already shows.
  if v_board.phase = 'sold' then raise exception 'lot_already_resolved' using errcode = 'P0001'; end if;

  if v_board.scoring_mode is distinct from 'weekly' then
    raise exception 'season_total_not_supported' using errcode = 'P0001';
  end if;

  select used_scout_token into v_used_scout
    from public.auction_players where match_id = p_match_id and user_id = v_user;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_used_scout or auction_private.tokens_used(p_match_id, v_user) >= v_board.token_count then
    raise exception 'no_scout_tokens' using errcode = 'P0001';
  end if;

  select position into v_position
    from public.auction_lots where match_id = p_match_id and seq = v_board.current_lot;
  if v_position is null then raise exception 'lot_not_found' using errcode = 'P0001'; end if;

  select points into v_points
    from private.auction_answers where match_id = p_match_id and seq = v_board.current_lot;

  v_tier := auction_private.weekly_tier(v_position, v_points);

  insert into public.auction_scouting_hints (match_id, seq, user_id, tier)
  values (p_match_id, v_board.current_lot, v_user, v_tier);

  update public.auction_players set used_scout_token = true
   where match_id = p_match_id and user_id = v_user;

  return v_tier;
end;
$function$;

-- ---------------------------------------------------------------- privileges --

revoke all on function auction_private.weekly_tier(text, numeric) from public, anon, authenticated;
revoke all on function auction.use_scout_token(uuid) from public, anon;
grant execute on function auction.use_scout_token(uuid) to authenticated;
