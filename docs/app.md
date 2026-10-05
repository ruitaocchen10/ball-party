# Ball Party

Ball Party is a sports (NFL) knowledge party game and community. People test their ball knowledge solo or with friends, and argue about it in a weekly prompt feed. It ships as a Next.js web app (`webapp/`), a native iOS app (`ios/`), and a Supabase backend (`supabase/`). Technical decisions live in [architecture](./architecture/architecture.md).

## Surfaces

**The Huddle (home, `/`).** A public feed of weekly prompts people answer and comment on: game picks, weekly picks, weekly awards, bold predictions, power rankings. Readable signed out; answering needs an account. Admins author and resolve prompts under `/admin`. The prompt kinds are `TemplateKind` in `webapp/lib/foundation/content/prompts/types.ts`.

**Games.** What each game is, who can play it, and whether it is live is the catalog in `webapp/lib/platform/orchestration/catalog.ts` (`status`, `solo`, `group`). Rules live in one doc per game:

| Game | Plays as | Rules |
| --- | --- | --- |
| Higher or Lower | solo or room, 2–4 | [higher_or_lower](./games/higher_or_lower/rules.md) |
| QB Season Builder | solo only | [qb_season_builder](./games/qb_season_builder/rules.md) |
| Auction Team Builder | room, 2–4 | [auction_team_builder](./games/auction_team_builder/rules.md) |
| Sabotage Draft | room, 2–4 | [sabotage_draft](./games/sabotage_draft/rules.md) |
| 2v2 Wavelength | room, 2 (co-op) or 4 (versus) | [wavelength](./games/wavelength/rules.md) |

Cards Against Humanity is not built: it has no catalog entry and no doc.

**Rooms (`/party`).** A host creates a room with a join code, friends join, and the host picks a game from the live room-capable games. Each pick starts an **arcade** run: one match of one game. See [lobbies](./architecture/lobbies/lobbies.md) for lobby → run → match.

**Solo (`/solo`, and the sidebar's solo section).** Starts a solo run of any game with `solo: true`. Signed-out visitors get a guest session on web.

**Profile (`/profile`).** Match history, stats, knower highlights and rankings, and the player's prompt takes.

## Accounts

Multiplayer needs a real account; guests are refused at `join_lobby` and `start_run`. Solo play works as a guest on web. iOS never carries a guest session.

## Not built yet

- **Party mode** (Mario Party style: a run of several minigames with points and a target score). The data model reserves a `party` run mode, but `start_run` raises `mode_not_supported` for anything except `arcade`. Orchestration of the party loop is unwritten (`orchestration.md` is a todo in architecture).
- **Party on iOS.** `LobbyScreen` is built but the Party tab shows a "coming soon" placeholder (`ios/BallParty/MainTabView.swift`).

## iOS

Four tabs: Home (Huddle), Games, Party (placeholder), Profile. Games on iOS are Higher or Lower (solo and live match) and QB Season Builder; the rest are web only. Layout in [`ios/BallParty/Games/README.md`](../ios/BallParty/Games/README.md).

## Keeping this file true

Update this file when a game goes live, a surface is added or removed, or party mode ships. Per-game rules belong in the game's own doc, and live/solo/group flags belong in the catalog; link to them rather than restating.
