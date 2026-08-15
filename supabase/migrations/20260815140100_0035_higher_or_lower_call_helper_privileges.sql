-- The policy resolves this definer helper without granting the caller direct
-- execution. Keep the engine schema's privilege boundary absolute: a player
-- may cause this question to be asked only through the calls SELECT policy.

revoke all on function higher_or_lower_private.has_called(uuid, smallint, uuid)
  from public, anon, authenticated;
