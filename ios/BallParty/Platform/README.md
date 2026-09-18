# Platform

Mirrors `webapp/components/platform` (lobbies → orchestration).
`Lobbies/` is the room: `LobbyClient` and its Supabase implementation, the
models, `LobbyViewModel`, and the screens for hosting, joining, and waiting
together (issue #65).

The room is also where a game gets started, and that means `LobbyViewModel`
knows one game by name: the platform freezes the roster (`start_run`) and the
game deals into the match it returns (`higher_or_lower.start`). Strictly that
is orchestration's job — "pick next game, launch match"
(`docs/architecture/architecture.md`) — and it sits here only because
orchestration isn't a module on either client yet; the web makes the same two
calls from the same place, in `webapp/lib/platform/lobbies/actions.ts`. It
moves when orchestration becomes real, on both clients together.

The dependency that is *not* negotiable runs the other way: a game may never
depend on this module. Which room a match belongs to reaches the match screen
as an argument from here, never by a game reading `lobbies`.
