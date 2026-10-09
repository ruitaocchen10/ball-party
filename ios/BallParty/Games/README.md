# Games

Mirrors `webapp/components/games`. Three games are on iOS:

- `HigherOrLower/`: the client protocol and its Supabase implementation, the
  models, the standings rules, and two screens (the solo run and the live
  multiplayer match), each with its own view model over the one shared client.
- `AuctionTeamBuilder/`: the live room match only (the auction has no solo
  mode). The client protocol and its Supabase implementation, the row models and
  the display-only board rules (`AuctionRules`, a port of the web's `board.ts`),
  the view model, and the screen.
- `QbSeasonBuilder/`: the solo run (spin reel, picks, staged result).

The other games (sabotage draft, wavelength) are web only. Rules live
on the server: see `docs/games/<game>/rules.md` and
`docs/architecture/architecture.md`.
