# Foundation

Mirrors `webapp/components/foundation` (identity · content · ui-kit); see
`docs/architecture/architecture.md`.

- `Identity/`: the sign-in gate, the session, and the profile.
- `Content/Prompts/`: **Huddle**, the `prompts` schema's prediction and take
  feed. `HuddleClient` is the one network seam. `PromptFeed` joins its flat rows
  into posts the way the web's `fetchPromptFeed` does and decides what a viewer
  may see yet. `HuddleViewModel` holds the feed and the picks and takes in
  progress. The screens are thin. Huddle is pure RPC/fetch (no Realtime, lobby
  or match), so the feed re-reads on appearing, on pull-to-refresh, and on
  returning to the app.
  - The feed shows the same post kinds as the web home. Authoring a prompt is
    admin-only on the web and out of scope here.
  - Power Rankings (`PowerRankingsViews`): the player ranks 5, 10 or all 32
    teams. Movement since their last ballot is matched by team code, because
    option ids are unique to each weekly post.
  - Once a prompt is answered or closed, the detail screen mirrors the web
    thread: the viewer's picks, take and points in one "You" card, then
    everyone else's takes with their tickets folded.
  - A game pick is drawn as on the web (`MatchupViews`, team logos and colours
    from `NFLTeams`). Venue, kickoff and Primetime come from `public.nfl_games`;
    `HuddleClient` never fails the feed over it, and a cover with no game says
    "Venue TBD".
- `UIKit/`: small platform shims.
