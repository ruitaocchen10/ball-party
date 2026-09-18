# Runtime

Mirrors `webapp/components/runtime` (realtime · game-runtime, the contract).

`GameRuntime/` holds `MatchClock` — the ported `useMatchClock`
timer/reconciliation state machine, a pure value type specified in
`docs/architecture/game-runtime.md` — and `MatchClockDriver`, the thin shell
that ticks it.

`Contract/` holds the decoding helpers every hand-written model needs to read
a PostgREST row, the closest this app has to the web's generated
`database.types.ts`. They live here, rather than in whichever module first
needed them, so `Games/` and `Platform/` can both depend on them without
depending on each other.

See `docs/architecture/architecture.md`.
