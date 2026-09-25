# Foundation

Mirrors `webapp/components/foundation` (identity · content · ui-kit) — see
`docs/architecture/architecture.md`.

- `Identity/` — the sign-in gate and the session.
- `Content/Prompts/` — **Huddle**, the `prompts` schema's prediction and take
  feed (issue #66). `HuddleClient` is the one network seam; `PromptFeed` joins
  its flat rows into posts the way the web's `fetchPromptFeed` does and decides
  what a viewer may see yet; `HuddleViewModel` holds the feed, the picks and
  takes in progress, and the guards on them; the screens are thin. Huddle is
  pure RPC/fetch — no Realtime channel, no lobby, no match — so the feed
  re-reads on appearing, on pull-to-refresh, and on returning to the app.
  The feed shows Picks and Power Rankings posts, as the web home does;
  posting a prompt is admin-only on the web and out of scope here
  (`game-runtime.md`). Power Rankings (`PowerRankingsViews`) is an
  opinion-only ranking where the player chooses to rank 5, 10 or all 32
  teams; movement since their last ballot is matched by team code, since
  option ids are unique to each weekly post.
  Once a prompt is answered or closed, the detail screen is laid out as the
  web's thread is: the viewer's picks, take and points in one "You" card (a
  Power Rankings board runs one column for 5 teams, two for 10 or 32), then
  everyone else's takes, whose tickets stay folded until asked for.
  A game pick is drawn as the web draws it (`MatchupViews`: the cut-corner
  ticket, team logos and colours from `NFLTeams`, a compact strip once it is a
  call). Its venue, kickoff and Primetime flag come from `public.nfl_games`,
  the schedule table the web reads too (migration 0119, filled hourly from
  nflverse by the same poll that auto-resolves picks). `HuddleClient` reads it
  for the games a feed's slots name and never fails the feed over it: with no
  game a cover says "Venue TBD".
- `UIKit/` — small platform shims.
