# Roadmap

Product management and upcoming features live in Jira on `ballparty.atlassian.net`, split across five projects: `BPR` (roadmap), `BPP` (product), `BPW` (web), `BPMO` (mobile) and `BPM` (marketing). Read them through the Jira MCP tools (e.g. `jira_search` with `project = BPP`).

# Orientation

Read `docs/app.md` first for what the product is and what is built. `docs/architecture/architecture.md` covers the stack, and `docs/games/<game>/rules.md` holds each game's rules.

Before any web UI work, read `docs/design/design-system.md`: the tokens, the `PageShell` page layouts, and the shared components in `webapp/components/foundation/ui-kit/`. Build screens from the kit rather than hand-styling markup. Color tokens exist in both `webapp/app/globals.css` and `ios/BallParty/Foundation/UIKit/Theme.swift`; change both together (a test enforces it).

# Web and iOS parity

The web and iOS apps must offer the same features and behavior; only layout may differ. `docs/features.yaml` lists every feature with a status per platform, and `docs/parity.md` has the rules. Any change to player-facing behavior updates `features.yaml` in the same change, and either touches both clients or records the gap there with a reason and a Jira ticket. Don't reimplement server rules in a client.

# Local development

## Database reset

When resetting the local Supabase stack, run `npm --prefix webapp run db:reset`. It applies migrations and `supabase/seed.sql`, then restores the NFL logo PNGs to the local `team-logos` Storage bucket. This is the complete local reset; `supabase db reset` alone leaves that bucket without its objects.
