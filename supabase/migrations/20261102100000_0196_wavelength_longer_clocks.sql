-- Wavelength clocks: 90s per clue (was 40) and 60s per guess (was 30).
-- Only the config changes; every phase transition reads these values, so
-- matches in progress keep their current deadline and the next phase
-- they enter picks up the new length.
create or replace function wavelength_private.config()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'scale_max',             1000,
    'wedge_width',           40,
    'clue_max_words',        8,
    'clue_max_chars',        100,
    'fill_seconds_per_clue', 90,
    'guess_seconds',         60,
    'versus_rounds',         8,
    'presets', jsonb_build_object(
      'short',  jsonb_build_object('rounds', 4, 'target',  8, 'star2', 12, 'star3', 15),
      'medium', jsonb_build_object('rounds', 6, 'target', 12, 'star2', 18, 'star3', 22),
      'long',   jsonb_build_object('rounds', 8, 'target', 20, 'star2', 24, 'star3', 29)
    )
  );
$$;
