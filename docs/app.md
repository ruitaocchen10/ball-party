# Ball Party

Ball Party is a sports (NFL) knowledge party game and community. People test their ball knowledge solo or with friends, and argue about it in a weekly prompt feed. It ships as a Next.js web app (`webapp/`), a native iOS app (`ios/`), and a Supabase backend (`supabase/`). Technical decisions live in [architecture](./architecture/architecture.md).

## Surfaces

**The Huddle (home, `/`).** Real accounts see two tabs, Huddle and Friends (`?view=friends`); Friends is the friend activity feed (`friend_activity`): friends' recent picks (never which options), pick results and match results from the last 30 days. The Huddle is a public feed of weekly prompts people answer and comment on: game picks, weekly picks, weekly awards, bold predictions, power rankings. Readable signed out; answering needs an account. Admins author and resolve prompts under `/admin`. The prompt kinds are `TemplateKind` in `webapp/lib/foundation/content/prompts/types.ts`.

**Games.** What each game is, who can play it, and whether it is live is the catalog in `webapp/lib/platform/orchestration/catalog.ts` (`status`, `solo`, `group`). Rules live in one doc per game:

| Game | Plays as | Rules |
| --- | --- | --- |
| Higher or Lower | solo or room, 2–4 | [higher_or_lower](./games/higher_or_lower/rules.md) |
| QB Season Builder | solo only | [qb_season_builder](./games/qb_season_builder/rules.md) |
| Auction Team Builder | room, 2–4 | [auction_team_builder](./games/auction_team_builder/rules.md) |
| Sabotage Draft | room, 2–4 | [sabotage_draft](./games/sabotage_draft/rules.md) |
| 2v2 Wavelength | room, 2 (co-op) or 4 (versus) | [wavelength](./games/wavelength/rules.md) |

Cards Against Humanity is not built: it has no catalog entry and no doc.

**Rooms (`/party`).** A host creates a room with a join code, friends join, and the host picks a game from the live room-capable games. Any member can invite friends from the lobby; the invitee sees pending invites at the top of `/party` and joins or declines (invites last 24 hours, in-app only, no push). Each pick starts an **arcade** run: one match of one game. See [lobbies](./architecture/lobbies/lobbies.md) for lobby → run → match.

**Solo (`/solo`, and the sidebar's solo section).** Starts a solo run of any game with `solo: true`. Signed-out visitors get a guest session on web.

**Profile (`/profile`).** Three tabs (`?tab=`): **Stats** (match history, knower highlights and rankings), **Takes** (the player's prompt takes) and **Friends** (see below). Edit profile also sets the player's unique **username**.

**Friends (the Friends tab on `/profile`).** Accounts only; guests are asked to sign up. Friends list, incoming and outgoing requests, blocked players, username search-as-you-type (prefix match from 3 characters, at most 8 suggestions) and a shareable invite link (`/friends/invite/<code>`, which stays its own page and opens in the iOS app via a Universal Link). The tab label shows a count of pending requests. `/friends` redirects to the tab. Rules live in SQL (migrations 0183 to 0191).

**Other players' profiles (`/u/<username>`).** Another player's highlights and match history. A private profile shows only its header to non-friends; unknown, guest and blocking users all look like not found (`get_profile`, migration 0186). Leaderboard rows link here.

**Leaderboard (`/leaderboard`).** Four boards, picked with `?board=`; each can be scoped to Everyone or Friends (the friends board ranks you against your accepted friends). Accounts only, not guests or signed-out visitors, and a private profile still ranks. Ranking and ties are in SQL.
- **Ball Knower** (default): resolved prompt points over the week, month, year or all time, with the viewer's own row and a 3-scored-pick floor (`ball_knower_leaderboard`, `my_ball_knower_standing`, migrations 0181 and 0182).
- **Wins** (`board=gamer`): multiplayer wins over the same windows. A win is first place in a completed non-solo match with at least two players; a tie for first counts for everyone tied. Shows games played beside wins (`gamer_leaderboard`, `my_gamer_standing`, migration 0192).
- **Higher or Lower** and **QB Season Builder** (`board=higher-or-lower`, `board=qb-season-builder`): each player's best solo run, all time, with no windows. Higher or Lower ranks the longest solo streak. QB Season Builder ranks the best season score, with a Visible / Hidden toggle (`mode=`) because the two modes are scored separately (`solo_leaderboard`, `my_solo_standing`, migration 0192).

## Accounts

Multiplayer needs a real account; guests are refused at `join_lobby` and `start_run`. Solo play works as a guest on web. iOS never carries a guest session. Guests cannot have friends or a username.

Every non-guest account has a unique username (3-20 letters, digits or underscores, case-insensitive): generated from the display name at signup, optionally chosen there, and confirmed once by existing users in a prompt. Settings has a **Private profile** switch (`set_profile_private`): only friends can open a private profile, but its name, username and photo stay searchable and it still ranks.

## Not built yet

- **Party mode** (Mario Party style: a run of several minigames with points and a target score). The data model reserves a `party` run mode, but `start_run` raises `mode_not_supported` for anything except `arcade`. Orchestration of the party loop is unwritten (`orchestration.md` is a todo in architecture).

## iOS

Four tabs: Home (Huddle | Friends), Games, Party (rooms), Profile. The leaderboard is reached from Profile → Your stats → Ball knower → View leaderboard, and a board picker at the top switches between the four boards. Friends and other players' profiles are in the Profile menu. Room invites work on iOS too: invite friends from the lobby, and the Party tab lists pending invites. iOS also opens friend invite links as Universal Links. Games on iOS are Higher or Lower (solo and live match) and QB Season Builder; the rest are web only. Layout in [`ios/BallParty/Games/README.md`](../ios/BallParty/Games/README.md).

## Keeping this file true

Update this file when a game goes live, a surface is added or removed, or party mode ships. Per-game rules belong in the game's own doc, and live/solo/group flags belong in the catalog; link to them rather than restating.
