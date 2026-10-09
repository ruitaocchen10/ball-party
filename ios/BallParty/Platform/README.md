# Platform

Mirrors `webapp/components/platform` (lobbies → orchestration).
`Lobbies/` is the room: `LobbyClient` and its Supabase implementation, the
models, `LobbyViewModel`, and the screens for hosting, joining, and waiting
together. `LobbyScreen` is the Party tab (`MainTabView.swift`).

The room is also where a game gets started: the platform freezes the roster
(`start_run`) and the game deals into the match it returns. So `LobbyViewModel`
knows which game it started, which strictly belongs to orchestration ("pick
next game, launch match"). It sits here because orchestration is not a module on
either client yet; the web makes the same two calls from
`webapp/lib/platform/lobbies/actions.ts`. It moves when orchestration becomes
real, on both clients together.

The dependency that is *not* negotiable runs the other way: a game may never
depend on this module. Which room a match belongs to reaches the match screen as
an argument from here, never by a game reading `lobbies`.
