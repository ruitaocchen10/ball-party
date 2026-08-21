-- Solo play (issue #32) needs its own run_mode: a run with nobody else in it,
-- started with no lobby at all.
--
-- This is its own migration, on its own, because a new enum label cannot be
-- referenced by any statement in the same transaction that added it — Postgres
-- refuses it outright rather than risk a value nobody has committed to yet.
-- Everything that actually reads 'solo' lands in 0044.
alter type public.run_mode add value 'solo';
