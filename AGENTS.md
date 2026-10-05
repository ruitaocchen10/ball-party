# Roadmap

Product management and upcoming features live in the Jira project `BP` ("ball-party") on `ruitaosworkspace-41168933.atlassian.net`. Read it through the Jira MCP tools (e.g. `jira_search` with `project = BP`).

# Orientation

Read `docs/app.md` first for what the product is and what is built. `docs/architecture/architecture.md` covers the stack, and `docs/games/<game>/rules.md` holds each game's rules.

# Local development

## Database reset

When resetting the local Supabase stack, run `npm --prefix webapp run db:reset`. It applies migrations and `supabase/seed.sql`, then restores the NFL logo PNGs to the local `team-logos` Storage bucket. This is the complete local reset; `supabase db reset` alone leaves that bucket without its objects.
