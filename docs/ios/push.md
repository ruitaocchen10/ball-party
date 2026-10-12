# iOS push notifications

Plumbing for GitHub #171 and sending for #172: how a device becomes reachable,
how a push is queued and sent, and what happens when it is tapped.

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
- **Profile → Notifications:** turns push on without waiting for the pre-prompt (it
  clears an earlier "Not now" and shows iOS's prompt), or opens iOS Settings once iOS
  has been told no. It re-registers an allowed device, so it also re-uploads the token.
- **One sheet at a time:** the pre-prompt is held back while the inbox or the
  username-confirm sheet is up and shows once they are dismissed.
- **Sign-out and account deletion:** the token is removed while the session still
  exists, the app badge is cleared, and APNs registration is dropped. If that call
  fails (offline) the token stays until another account registers this device.
- **Badge:** the unread inbox count.
- **Tap:** opens the inbox and lands on the same page the row would
  (`InboxDestination.resolve`), then marks the item read.

## Sending (#172)

Four events send a push: a new prompt, a friend request, a room invite and a reply
to your take.

1. **Queue.** Triggers (and `prompts.create_post` for a new prompt) write
   `public.push_outbox` in the same transaction as the event (migration 0206).
   Only people with a registered device get a row. Every enqueue swallows its own
   errors, so a problem here can never fail the friend request, invite, reply or
   post behind it. The inbox row is written regardless and stays the source of truth.
2. **Coalescing.** A reply waits 30 seconds, and an unclaimed row is unique per
   (recipient, kind, item), so a burst of replies to one take is one push. A reply
   after the owner has read the item is a new push.
3. **Suppression.** Decided when a row is claimed, not when it is written: a block
   in either direction, a deleted account, an inbox item that is no longer unread
   (read, answered, declined, expired) and a prompt that has locked all drop the
   push. Rows older than an hour are dropped as stale.
4. **Drain.** `pg_cron` runs `private.push_drain_tick()` every 15 seconds, which
   posts to the `send-push` Edge Function through `pg_net` when something is due.
   The function claims a batch (`claim_push_batch`), sends each push to each of the
   recipient's devices over HTTP/2 (sandbox tokens to the sandbox host, production
   to production), and reports `sent`, `retry` or `dead` (`finish_push`). A push is
   sent if any device accepted it. Retries back off 30 seconds per attempt and stop
   after five. Tokens APNs rejects (410, `BadDeviceToken`, `Unregistered`) are deleted.
5. **Admin.** The create-post form has a "Send a push notification" checkbox, on by
   default; unticked passes `p_send_push => false` and nothing is queued.

Where the logic lives: what to send and to whom is Postgres (`supabase/tests/0206_push_outbox.test.sql`);
building payloads and talking to APNs is `supabase/functions/send-push/` (tested in
`webapp/test/edge/send-push.test.ts`, since everything but `index.ts` is plain
TypeScript on web-standard APIs).

### Payload contract

Alerts use fixed, generic copy (no names or take text on a lock screen). Keys beside
`aps` that the app reads (`PushPayload`):

| key | meaning |
| --- | --- |
| `kind` | `friend_request`, `take_reply`, `room_invite` or `new_prompt` |
| `item_key` | the inbox item (`n:<uuid>` / `i:<uuid>`); not sent for `new_prompt` |
| `post_id` | `new_prompt`: the post |

`aps.badge` is the recipient's unread inbox count. A tap on an inbox kind reads the
item and opens its page from the inbox (a room invite opens the inbox itself); a
`new_prompt` opens Home. `apns-collapse-id` is the item key (or the prompt) so a repeat
replaces the alert still on screen.

### Deploying

1. `scripts/apns/setup.sh` stores the APNs secrets, a shared `PUSH_FUNCTION_SECRET`,
   deploys the function with `--no-verify-jwt`, and prints the SQL that gives the
   database the function URL and secret (Vault: `push_function_url`,
   `push_function_secret`).
2. Until those two Vault secrets exist, the drain tick does nothing.

## Local stack

Nothing calls APNs unless you set it up. The local database takes
`register_device_token` like any RPC and queues pushes into `push_outbox` as usual;
without the Vault secrets the drain tick does nothing and the outbox ages out after an
hour. A simulator or unsigned build that can't get a token just logs the failure
(`push` category) and carries on. To try the sender locally, run
`supabase functions serve send-push --env-file <file with the APNS_* secrets>` and call it
with the `x-push-secret` header; real delivery needs a physical device.
