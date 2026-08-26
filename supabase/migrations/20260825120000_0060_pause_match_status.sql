-- A new `match_status` value for a host-paused match. Split into its own
-- migration/transaction on purpose: Postgres will not let a later statement
-- in the *same* transaction reference a value just added via `ADD VALUE`, and
-- 0061 (the pause/resume RPCs) needs to reference 'paused' immediately.
alter type public.match_status add value 'paused';
