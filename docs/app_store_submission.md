# App Store submission — materials checklist

Working checklist for submitting Ball Party (iOS) to the App Store. Split into
what's done, copy-paste text for App Store Connect, and what only you can do
(Apple accounts and payments aren't something an agent can hold).

## Already in place (verified in this repo)

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
| Build | `xcodebuild build` for the iPhone 18 Pro Max simulator succeeds as of this session |

## Built this session

- **Privacy Policy** — `webapp/app/privacy/page.tsx` → will be live at `https://ballparty.social/privacy`
- **Support page** — `webapp/app/support/page.tsx` → will be live at `https://ballparty.social/support`
- Both added to `PUBLIC_PATHS` in `webapp/lib/supabase/proxy.ts` so they're reachable signed-out (App Review must be able to open them without an account) — confirmed 200 locally, existing test suite still green.
- One real App Store screenshot at the required 6.9" size (1320×2868), captured from the simulator: the sign-in screen. Saved at `/private/tmp/claude-503/-Users-ruitao-ball-party/3f33b32a-1972-4f51-accb-b802b3fb8a47/scratchpad/screenshots/01-sign-in.png` — copy it out of the scratchpad before the session ends.

Contact address on both pages is `testytesttesty9021@gmail.com`.

## App Store Connect — copy/paste metadata

**Category:** Games → Trivia (Word or Sports are reasonable alternates if Trivia feels off)

**Subtitle** (30 char max): `Sports takes, stat games, wins`

**Promotional text** (170 char max, editable without a new build):
> Post your NFL picks and Power Rankings, then see who called it. Plus two stat-driven solo games: QB Season Builder and Higher or Lower.

**Description:**
```
Ball Party is the group chat that keeps score.

Post your picks on this week's NFL games and your Power Rankings ballot, then see who actually called it once the picks lock — every take gets graded.

Play stat-driven games on your own:

• QB Season Builder — spin a random team's season six times and build one quarterback from the best trait offered at every stop.
• Higher or Lower — call whether the next card's fantasy total is higher or lower and keep the streak alive.

Sign in with Apple, Google, or email — no ads, just the takes and the games.
```

*(Party Mode — lobbies, playing mini-games live with friends Mario-Party style — is built server-side but not yet turned on in the iOS app; the Party tab currently shows a "coming soon" placeholder. Leave it out of the description until that ships, or App Review will flag it as advertising a feature the build doesn't have.)*

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
target; no camera, photo library, contacts, location, or microphone API is
used anywhere in `ios/BallParty`.

| Data type | Collected? | Linked to identity | Used for |
| --- | --- | --- | --- |
| Contact Info → Email Address | Yes | Yes | App Functionality (account) |
| Identifiers → User ID | Yes | Yes | App Functionality |
| Identifiers → Name (display name) | Yes | Yes | App Functionality |
| User Content → Other User Content (takes, picks, draft results) | Yes | Yes | App Functionality |
| Everything else (Location, Contacts, Photos, Health, Financial Info, Browsing/Search History, Usage Data, Diagnostics, etc.) | No | — | — |
| **Data used to track you** | **No** | — | — |

None of it is used for tracking, and it isn't sold. If you add analytics
(even Vercel Analytics-style pageviews) to the iOS binary later, revisit this
table — right now that only runs in the webapp, not the app.

## Age rating questionnaire

Nothing in the game content (sports trivia/stats, no user-generated media,
no chat with strangers beyond takes/picks visible to lobby members) should
trigger anything above the default **4+** rating. Answer "None"/"No" to all
of: cartoon/fantasy/realistic violence, mature themes, gambling, horror,
alcohol/tobacco/drugs. Say **Yes** to "Unrestricted Web Access" only if any
in-app browser sheet can hit arbitrary URLs (check `ASWebAuthenticationSession`
usage in `AuthBackend`/`AuthViewModel` — it's OAuth-only, opens Apple/Google's
own domains, so "No" is correct here too).

## Screenshots — what's left

Required set for iPhone-only: **6.9" display** (1320×2868), 3–10 images.
One is captured (sign-in). The rest need a signed-in session with real game
data, which needs either:

1. The local Supabase stack running (`npm --prefix webapp run db:reset`) plus
   a demo account signed in via email/password (Apple/Google can't be
   scripted in Simulator) — then I drive the simulator screen-by-screen, or
2. You grab them yourself in a few minutes: `Cmd+R` in Xcode on an iPhone 18
   Pro Max (or any 6.9" sim/device), sign in, and `Cmd+S` on each screen you
   want (Home/Huddle, Party lobby, one game in progress, a finished
   take/result). That's usually faster than scripting simulator taps.

Say the word if you want me to push further on option 1 — it means starting
the local backend and driving the simulator via computer-use, which takes a
few more steps and won't be as fast as you just tapping through it yourself.

## What only you can do

- Confirm the App Store Connect app record's name/bundle ID/SKU match the
  above (you said the record already exists).
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
