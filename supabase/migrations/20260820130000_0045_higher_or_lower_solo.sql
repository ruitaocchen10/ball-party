-- Solo play, Higher or Lower's side. See issue #32.
--
-- The dealer's floor was 2 because every match used to come from a lobby, and
-- a lobby's own floor (`start_run`, 0009) is 2. `start_solo_run` (0044) skips
-- that check by construction — it seats exactly one player and never touches
-- a lobby — so the only thing left refusing a solo deal is this function's own
-- floor. It drops to 1.
--
-- The match records whether it was solo. `higher_or_lower_matches` already
-- carries the format a match was dealt with rather than pointing at whatever
-- the game's defaults are today (see 0032's header) — this is one more fact
-- of that shape. It is read off the dealt roster itself (`v_n = 1`) rather
-- than off `runs.mode`: the deal already counts the roster for the floor
-- check above, and asking the platform what mode its own run is in would be
-- this schema reaching for something the two-table split (0032) exists to
-- keep it from needing.
--
-- Rebuilt from its current definition, the way 0040 rebuilt it for weekly
-- scoring — this changes two small spots in a large function, and copying the
-- whole body by hand is exactly how 0045's first draft silently reverted 0040's
-- weekly deck. Patching the live definition can't drift from it.

alter table public.higher_or_lower_matches
  add column is_solo boolean not null default false;

do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'higher_or_lower_private.deal_board(uuid,double precision,text,smallint,smallint)'::regprocedure
  ) into definition;

  definition := replace(
    definition,
    $$  -- The platform already refused a one-person lobby. This is the game's own
  -- floor, which belongs here rather than there: the platform must not learn
  -- what any particular game needs.
  if v_n < 2 then
    raise exception 'too_few_players' using errcode = 'P0001';
  end if;$$,
    $$  -- This game's own floor, which belongs here rather than in the platform:
  -- the platform must not learn what any particular game needs. It is 1
  -- rather than 2 because solo (#32) is a legitimate one-player ladder; a
  -- lobby-backed run still cannot reach this with fewer than 2, because
  -- `start_run` refused it first.
  if v_n < 1 then
    raise exception 'too_few_players' using errcode = 'P0001';
  end if;$$
  );

  definition := replace(
    definition,
    $$  insert into public.higher_or_lower_matches (
    match_id, question_count, spare_count, current_question,
    scoring_mode, season_from, season_to
  )
  values (
    p_match_id, v_question_count, v_spare_count, 1,
    p_scoring_mode, v_from, v_to
  );$$,
    $$  insert into public.higher_or_lower_matches (
    match_id, question_count, spare_count, current_question,
    scoring_mode, season_from, season_to, is_solo
  )
  values (
    p_match_id, v_question_count, v_spare_count, 1,
    p_scoring_mode, v_from, v_to, v_n = 1
  );$$
  );

  execute definition;
end;
$migration$;
