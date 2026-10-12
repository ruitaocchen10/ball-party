# iOS push notifications

Plumbing for GitHub #171. Sending is #172; this covers how a device becomes
reachable and what happens when a push is tapped.

## Owner setup (once)

Run `scripts/apns/setup.sh`. It walks through enabling Push Notifications on the
`com.ballparty.app` app ID, creating the APNs auth key (.p8), and storing
`APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_BUNDLE_ID` as Supabase
secrets. The `aps-environment` entitlement is in `ios/BallParty/BallParty.entitlements`;
Xcode's automatic signing rewrites it to `production` for TestFlight and App Store builds.

## Device tokens

`public.device_tokens` (migration 0205) has one row per install and APNs
environment. Clients have no table grants; they call `register_device_token` and
`unregister_device_token`. Registering a token from another account moves it, so a
shared device never keeps the previous person's pushes. The sender removes tokens
APNs reports as dead with `delete_device_tokens` (service role only).

Debug builds register as `sandbox`, release builds as `production`. A token only
works against the matching APNs host, so the sender picks the host from the row.

## In the app

`PushCoordinator` (`Foundation/Notifications/`) owns it all:

- **Launch:** if notifications are allowed it registers with APNs and uploads the
  token (this refreshes `last_seen` and picks up a rotated token). If the player
  has since turned them off in Settings, the token is removed from the server.
- **Permission:** never at launch. After the first meaningful action (locking in a
  pick, making or joining a room, adding a friend) a short pre-prompt explains why;
  only "Turn on notifications" spends iOS's one system prompt. "Not now" asks again
  after 14 days.
- **Sign-out and account deletion:** the token is removed while the session still
  exists, the app badge is cleared, and APNs registration is dropped. If that call
  fails (offline) the token stays until another account registers this device.
- **Badge:** the unread inbox count.
- **Tap:** opens the inbox and lands on the same page the row would
  (`InboxDestination.resolve`), then marks the item read.

## Payload contract for #172

Keys beside `aps` that the app reads (`PushPayload`):

| key | meaning |
| --- | --- |
| `kind` | `friend_request`, `take_reply` or `room_invite` |
| `item_key` | the inbox item key (`n:<uuid>`), so a tap marks it read |
| `username` | friend_request: the requester's username |
| `post_id`, `ref_id` | take_reply: the prompt post and the take |

A payload with no usable destination opens the inbox. `aps.badge` should be the
recipient's `inbox_unread_count()`.

## Local stack

Nothing here calls APNs. The local database takes `register_device_token` like any
RPC, and a simulator or unsigned build that can't get a token just logs the
failure (`push` category) and carries on. Real delivery needs a physical device.
