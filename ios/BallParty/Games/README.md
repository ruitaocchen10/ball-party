# Games

Mirrors `webapp/components/games`. Two games are on iOS:

- `HigherOrLower/`: the client protocol and its Supabase implementation, the
  models, the standings rules, and two screens (the solo run and the live
  multiplayer match), each with its own view model over the one shared client.
- `QbSeasonBuilder/`: the solo run (spin reel, picks, staged result).

The other games (auction, sabotage draft, wavelength) are web only. Rules live
on the server: see `docs/games/<game>/rules.md` and
`docs/architecture/architecture.md`.
