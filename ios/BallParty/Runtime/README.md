# Runtime

Mirrors `webapp/components/runtime` (realtime · game-runtime, the contract).
`GameRuntime/` holds `MatchClock` — the ported `useMatchClock`
timer/reconciliation state machine, a pure value type specified in
`docs/architecture/game-runtime.md` — and `MatchClockDriver`, the thin shell
that ticks it. See `docs/architecture/architecture.md`.
