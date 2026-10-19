# App Store submission — materials checklist

Checklist for submitting Ball Party (iOS) to the App Store: what's in place,
copy-paste text for App Store Connect, and what only the account holder can do
(Apple accounts and payments aren't something an agent can hold).

## In place in the repo

| Item | Value |
| --- | --- |
| Bundle ID | `com.ballparty.app` |
| Display name | Ball Party |
| Version / build | 1.0 / 1 |
| Team | `NS8CC9Z25V` |
| Min iOS | 17.0 |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) — no iPad screenshots needed |
| App icon | 1024×1024 present at `ios/BallParty/Assets.xcassets/AppIcon.appiconset/AppIcon.png` |
| Sign in with Apple | Entitlement present, implemented in `Foundation/Identity` |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` added to `Info.plist` (standard HTTPS only, no custom crypto) |

## Web pages Apple checks

- **Privacy Policy**: `webapp/app/privacy/page.tsx`, at `https://ballparty.social/privacy`.
- **Support page**: `webapp/app/support/page.tsx`, at `https://ballparty.social/support`.
- Both are in `PUBLIC_PATHS` in `webapp/lib/supabase/proxy.ts`, so App Review can
  open them signed out.

Contact address on both pages is `testytesttesty9021@gmail.com`.

## App Store Connect — copy/paste metadata

**Category:** Games → Trivia (Word or Sports are reasonable alternates if Trivia feels off)

**Subtitle** (30 char max): `Sports takes, stat games, wins`

**Promotional text** (170 char max, editable without a new build):
> A fresh slate of NFL prompts every week. Make your picks, rank the league, and bid against friends in the auction. Who really knows ball?

**Description:**
```
The group chat, but it keeps score.

Ball Party is where NFL fans prove they know ball. Make your calls, argue about them with friends, and see who was right.

EVERY WEEK, GO ON THE RECORD
Answer weekly prompts: pick game winners, hand out weekly awards, make bold predictions and rank the league. Prompts lock when the games start, so every call counts.

SEE WHO CALLED IT
Your feed shows which friends answered each prompt. Give a ball for a great take and take one away for a bad one. Your balls and correct picks build your Ball Knower score on the leaderboard.

RANK THE LEAGUE
Keep a living power ranking and top 10 lists for QBs, RBs and WRs. Share your updates with friends and defend your list when they reply.

PLAY STAT GAMES
• Higher or Lower: call whether the next player's season beat the last, solo or with friends.
• QB Season Builder: spin team-seasons and build the best quarterback you can.
• Auction Team Builder: bid on mystery players against 1 to 3 friends. Their fantasy points stay hidden until the lot sells.
• 2v2 Wavelength: give a one-shot clue and find the hidden target, co-op or head to head.

BRING YOUR FRIENDS
Start a party room, invite friends, and pick a game. Climb the leaderboards for Ball Knower points, multiplayer wins and solo high scores.

Sign in with Apple, Google or email.

Ball Party is not affiliated with or endorsed by the NFL or any NFL team.
```

*(Only describe what the build has. Party mode, a run of several minigames with a target score, is not built, and neither is Cards Against Humanity, so keep both out of the description. The games listed above match the catalog in `docs/app.md`.)*

**Keywords** (100 char max, comma-separated, no spaces needed):
`sports,nfl,trivia,fantasy football,stats,picks,rankings,quiz,football`

**Support URL:** `https://ballparty.social/support`
**Marketing URL:** `https://ballparty.social`
**Privacy Policy URL:** `https://ballparty.social/privacy`

**Copyright:** `© 2026 Ball Party`

**What's New (v1.0):** `First release.`

## App Privacy ("nutrition label") answers

Based on an audit of the iOS code: auth is Supabase (email/password, Sign in
with Apple, Google OAuth); no analytics/crash/ad SDK is linked into the iOS
target; no camera, contacts, location, or microphone API is used anywhere in
`ios/BallParty`. Two features do collect data beyond the account: the profile
editor uploads an avatar chosen with `PhotosPicker`, and push notifications
register a device token (`register_device_token`).

Answer App Store Connect to match `ios/BallParty/PrivacyInfo.xcprivacy`, which
declares the same set. If the two disagree, Apple can flag the mismatch.

| Data type | Collected? | Linked to identity | Used for |
| --- | --- | --- | --- |
| Contact Info → Email Address | Yes | Yes | App Functionality (account) |
| Contact Info → Name (display name) | Yes | Yes | App Functionality |
| Identifiers → User ID | Yes | Yes | App Functionality |
| Identifiers → Device ID (push token) | Yes | Yes | App Functionality |
| User Content → Photos or Videos (profile avatar) | Yes | Yes | App Functionality |
| User Content → Other User Content (takes, replies, ranking lists, reports) | Yes | Yes | App Functionality |
| User Content → Gameplay Content (match results, scores, streaks) | Yes | Yes | App Functionality |
| Everything else (Location, Contacts, Health, Financial Info, Browsing/Search History, Usage Data, Diagnostics, etc.) | No | — | — |
| **Data used to track you** | **No** | — | — |

None of it is used for tracking, and it isn't sold. If you add analytics
(even Vercel Analytics-style pageviews) to the iOS binary later, or any other
data collection, revisit this table and `PrivacyInfo.xcprivacy` together; right
now analytics only runs in the webapp, not the app.

## Age rating questionnaire

The game content (sports trivia and stats) is mild, but the app has
**user-generated content**: players post takes and replies that other players
read, and profiles are searchable by username. Answer the questionnaire's
user-generated-content and messaging questions truthfully (Yes), and let Apple
compute the rating from the answers; do not assume 4+.

What the app has for that, which Apple's UGC guideline (1.2) expects: a Report
button on every take, reply and profile, blocking, a banned-terms filter on new
takes, and an admin report queue (see "Safety and moderation" in `docs/app.md`).
Mention them in the review notes.

Answer "None"/"No" to the rest: cartoon/fantasy/realistic violence, mature
themes, gambling (no money is involved; revisit if that ever changes), horror,
alcohol/tobacco/drugs. "Unrestricted Web Access" is **No**: the only in-app web
sessions are the OAuth sheets (`ASWebAuthenticationSession` in
`AuthBackend`/`AuthViewModel`, Apple/Google's own domains), and the Privacy,
Terms and Support links open in Safari.

The questionnaire's wording changes between Apple releases, so check the
current form rather than relying on this list.

## Screenshots

The current set is three captioned, framed slides: friends feed, power rankings
and Auction Team Builder. They are built in `marketing/app-store/screenshots.html`
from simulator captures in `marketing/app-store/shots/`, and the exported PNGs are
in `marketing/app-store/export/`.

**Size.** The "iPhone with Dynamic Island (medium display)" slot in App Store
Connect rejected 1320×2868 ("File dimensions are invalid"). It accepts 1206×2622
or 1179×2556 portrait, so the page exports at **1206×2622** with no alpha.

**Recapturing.** Run the app on an iPhone 18 Pro Max simulator against the local
stack (`npm --prefix webapp run db:reset`), sign in as `demo@ballparty.local` /
`ball-party-demo` (Apple and Google sign-in can't be scripted in Simulator), set
the clock with `xcrun simctl status_bar <udid> override --time 9:41 ...`, and
capture with `xcrun simctl io <udid> screenshot`. The auction needs 2 to 4
players: seat seeded friends by calling `join_lobby` as each user from SQL, and
place their bids with `auction.place_bid`. Then re-render each slide in headless
Chrome at `screenshots.html?export&only=<feed|rankings|games>` with a
1206×2622 window.

## What only you can do

- Confirm the App Store Connect app record's name/bundle ID/SKU match the
  above (the record already exists).
- Pricing: Free, no IAP — set territory availability in Connect.
- Fill in the metadata fields above in App Store Connect.
- Deploy the webapp (so `/privacy` and `/support` are actually live) before
  submitting — Apple will check the URLs.
- Archive and upload the build via Xcode Organizer or `xcodebuild -archive` +
  Transporter; this needs your Apple ID / team signing in Xcode.
- Complete the App Privacy questionnaire and age rating questionnaire in
  Connect using the tables above.
- Submit for review, and answer the encryption question on upload if asked
  (should now auto-answer "No" thanks to the `Info.plist` key).
