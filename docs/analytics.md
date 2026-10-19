# Product analytics

Usage analytics go to [PostHog](https://posthog.com) (US cloud), one project for
both clients. App Store Connect covers the store funnel (impressions, downloads,
retention); PostHog covers what people do once they are in the app.

## What is sent

Only the events in [`analytics/events.json`](./analytics/events.json), plus page
views on the web. No autocapture, session replay, feature flags, surveys,
lifecycle or screen-view events, and no IP-based location. Every event carries
`platform` (`web` or `ios`). The person is the Supabase user id (lower-case, the
same string on both clients), never an email or a name.

| Event | When | Properties |
| --- | --- | --- |
| `signed_up` | An account is created: email confirmation completed, or a first Apple/Google sign-in | `method` |
| `signed_in` | Email, Google or Apple sign-in to an existing account | `method` |
| `party_created` | A host creates a room | |
| `party_joined` | A player joins a room | |
| `game_started` | A match is dealt, in a room or solo | `game`, `solo` |
| `prompt_answered` | A prompt answer or Bold Predictions is submitted | `post_id` |
| `take_posted` | A reply to a take is posted | `post_id`, `is_reply` |
| `invite_link_shared` | A friend or room invite link is shared or copied | `kind` (`friend`, `room`) |
| `invite_accepted` | A friend invite is redeemed | `kind`, `result` |
| `push_enabled` | iOS only: the player allows notifications | |

## Where it lives

|  | Web | iOS |
| --- | --- | --- |
| Entry point | `webapp/lib/foundation/analytics/client.ts` (`track`, `identify`) and `server.ts` (`trackServer`) | `Analytics.shared.track(_:_:)` in `ios/BallParty/Foundation/Analytics/` |
| Init | `webapp/instrumentation-client.ts` | `BallPartyApp.init` |
| Identity | `AnalyticsIdentity` follows Supabase auth state | `AuthViewModel.session` `didSet` |
| Vendor code | `posthog-js`, `posthog-node` | `PostHogAnalyticsSink.swift` only |

Web sends lobby, game and sign-in events from server actions and route handlers
through `trackServer`, because those end in a redirect and there is no client
code left to report them. It runs in `after()`, so it never delays the response.

## Setup

Create the project at us.posthog.com, then in its settings turn on
**Discard client IP data**. Put the project token (`phc_...`, safe to ship) in:

- `webapp/.env.local` and the Vercel project: `NEXT_PUBLIC_POSTHOG_KEY`
- `ios/Secrets.xcconfig` and `ios/Secrets.release.xcconfig`: `POSTHOG_API_KEY`

With no key, nothing is loaded and nothing is sent. iOS also sends nothing while
running unit tests.

## Opting out

"Share usage data" is a switch on each client (web Settings, iOS Profile →
Privacy). It is kept on the browser or device, not the account. Both clients keep
the choice themselves (a cookie, `UserDefaults`) rather than in the PostHog SDK,
because the SDK's `reset()` on sign-out clears its own stored consent. The web
server reads the cookie before sending any event.

## Adding or changing an event

1. Edit `analytics/events.json` (name, platforms, properties).
2. Add it to `AnalyticsEvents` and `WEB_EVENT_NAMES` in
   `webapp/lib/foundation/analytics/events.ts`, and to `AnalyticsEvent` in
   `AnalyticsEvent.swift`. The test on each side fails until they match the JSON.
   Property keys are not machine-checked, so keep them identical by hand.
3. Call it at the same moment on both clients, or record the gap in
   `features.yaml`.
4. If it adds a new kind of data, revisit `webapp/app/privacy/page.tsx`,
   `ios/BallParty/PrivacyInfo.xcprivacy` and the table in
   `docs/ios/app_store_submission.md`.
