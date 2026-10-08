# Web and iOS parity

The web app (`webapp/`) and the iOS app (`ios/`) should offer the same features
and behave the same way. Layout and navigation are free to differ. This doc is
how we keep them from drifting.

## What counts as the same

- **Features.** If a player can do something on one client, they can on the
  other, unless the gap is recorded as a decision.
- **Behavior and rules.** Game rules, scoring, timers, who can do what, and
  error cases. These come from the server, so a client should never reimplement
  them.
- **Content and copy** where it carries meaning: game names, mode names, what a
  setting does.

Not required to match: layout, navigation, gestures, animation, component
structure, platform conventions (Sign in with Apple, share sheets).

## The sources of truth

| What | Lives in | Notes |
| --- | --- | --- |
| Rules and state | Postgres RPCs and projections (`supabase/`) | Both clients call these. Never enforce a rule client-side. |
| What the product does | [`features.yaml`](./features.yaml) | One entry per feature, with a status per platform. |
| Game rules in prose | `docs/games/<game>/rules.md` | Update with any rules change. |
| Which games are live | `webapp/lib/platform/orchestration/catalog.ts` | iOS currently copies this by hand. |
| Colour tokens | `globals.css` and `Theme.swift` | A test compares them. |

## Working rules

1. **Add a feature on one client, add its entry to `features.yaml` in the same
   change.** If the other client's status isn't `done`, set it to `missing` (we
   owe it) or `no` with a reason. Silence is not an option.
2. **A behavior or rules change** updates the server, `rules.md`, and both
   clients, or says in the PR which client is deferred and files a ticket.
3. **Gaps get tickets.** Every `missing` or `partial` entry should have a Jira
   ticket (iOS gaps go in `BPMO`, web gaps in `BPW`). Put the ticket key in the entry's `ticket:` field.
4. **`no` needs a reason** a future reader can judge. "Haven't gotten to it" is
   `missing`, not `no`.
5. **Don't copy server facts into a client.** If iOS needs a list the server or
   catalog already owns (kinds, modes, eras), read it from the server or add a
   test that compares the two copies, the way `tokens.test.ts` does for colours.
6. **When a feature ships on the second client, flip its status** and delete the
   stale `note`.

## Review checklist

For any PR that changes player-facing behavior:

- Does `features.yaml` still tell the truth?
- Did the change touch an RPC, table or state shape? Does the other client still
  decode it?
- Did it change copy, modes or options that the other client duplicates?
- If only one client changed, is the other's gap recorded and ticketed?

## Status and what's still manual

`features.yaml` is currently checked by people. The next steps, in order of
value, are a test that every `done` entry has a marker in that platform's code,
iOS tests running in CI, and contract tests between RPC shapes and the iOS
models. Until those exist, the checklist above is the enforcement.
