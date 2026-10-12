# Games

Mirrors `webapp/components/games`. Every game is on iOS:

- `HigherOrLower/`: the client protocol and its Supabase implementation, the
  models, the standings rules, and two screens (the solo run and the live
  multiplayer match), each with its own view model over the one shared client.
- `AuctionTeamBuilder/`: the live room match only (the auction has no solo
  mode). The client protocol and its Supabase implementation, the row models and
  the display-only board rules (`AuctionRules`, a port of the web's `board.ts`),
  the view model, and the screen. The live board is a pinned header over three
  native tabs (Auction, Table, Board) built on `Foundation/UIKit/GameTabs.swift`,
  the shared shell the other games should use too.
- `Wavelength/`: the live room match only (co-op or 2v2). The client protocol
  and its Supabase implementation (including the private broadcast channel the
  guesser's needle rides), the row models and the display-only dial rules, the
  view model, and the screen: a pinned header over two native tabs (Dial,
  Rounds) on the same `GameTabs.swift` shell. The dial is drawn and dragged in
  `WavelengthDial`; the hidden target only ever reaches its psychic, because
  row-level security narrows it before the app reads anything.
- `QbSeasonBuilder/`: the solo run (spin reel, picks, staged result).

Rules live
on the server: see `docs/games/<game>/rules.md` and
`docs/architecture/architecture.md`.
