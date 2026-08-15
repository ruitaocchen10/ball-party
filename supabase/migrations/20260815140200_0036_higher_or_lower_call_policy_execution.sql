-- PostgreSQL evaluates a policy expression as the requesting role, so its
-- definer helper still needs EXECUTE. The private schema itself has no USAGE
-- grant, which keeps this from becoming a callable API surface.

grant execute on function higher_or_lower_private.has_called(uuid, smallint, uuid)
  to authenticated;
