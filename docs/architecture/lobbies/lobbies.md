# Lobbies

How players are grouped, and how their play is structured over time. Applies to
every game in [`games/`](../../games/); no game defines its own lobby.

## Three levels

```
lobby        the room — people, code, durable
  └── run    one sitting of one mode — arcade or party
        └── match    one playthrough of one game
```

**Why not collapse lobby and run?** A group will play a quick arcade game and
then want a full party. If the room _is_ the party, switching modes means
leaving, re-creating, re-sharing the code, and everyone rejoining — right when
the group is warmed up and most likely to keep playing.

## Decided

**The lobby has no mode.** You pick arcade or party when you start a run, from
inside the room. That defers the choice until you know how many people showed up
and how much time they have.

**Two rosters.** Lobby membership (who's in the room) is not run participation
(who's playing this sitting).

The run takes a **snapshot** of the roster at start and never asks the lobby
again. So a player joining mid-party isn't turned away — they sit in the room,
watch, and are in for the next run. A player who leaves mid-party stays a run
participant, so their points stand and the standings still make sense.

`run_participants` is that snapshot. The roster freeze is structural, not a rule
anyone has to remember.
