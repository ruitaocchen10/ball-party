# Games

Mirrors `webapp/components/games` (auction · wavelength · higher-or-lower ·
cah). `HigherOrLower/` holds the client protocol and its Supabase
implementation, the models, the standings rules, and two screens: the solo run
(issue #64) and the live multiplayer match (issue #65), each with its own view
model over the one shared client.

See `docs/architecture/architecture.md`, and `docs/games/higher_or_lower.md`
for the rules themselves — which live on the server, not here.
