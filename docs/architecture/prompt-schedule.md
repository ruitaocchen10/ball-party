# Prompt schedule (admin calendar)

BPP-15. An admin calendar for planning weekly prompts ahead, so the week's mix is visible and nothing is forgotten. Web only; publishing stays manual: a prompt goes live only after an admin marks it ready, and then it opens at its time. The product view is in [app.md](../app.md#admin-calendar-web-only-admin); this is how it works.

## Why a separate table

Drafts live in `prompts_private.schedule_slots`, **not** in `public.prompt_posts`. Many security-definer readers (feeds, leaderboards, notifications) assume every `prompt_posts` row is a real prompt, so a draft or ready row there could reach players through any reader that missed a status filter. In the planning table nothing player-facing reads it, so a draft cannot leak. A prompt enters `prompt_posts` only when it opens, through the same `prompts.create_post` as one published by hand.

## Slots

One row per `(season, week, kind, game)`, unique, so pre-filling again adds nothing. Kinds: `game_pick` (one per game, `game_id` set), `weekly_picks`, `weekly_awards`, `bold_predictions`, `power_rankings`.

Stored state: `empty` -> `draft` -> `ready` -> `published`.

| Transition | RPC (admin only) |
| --- | --- |
| empty/ready -> draft | `schedule_save_draft` (a ready slot edited drops back to draft) |
| draft -> ready | `schedule_mark_ready`: needs a caption, resolution criteria, an open time before the lock time, a game for game picks, and passes a dry run of `create_post` (rolled back) |
| ready -> draft | `schedule_unready` |
| draft/ready -> empty | `schedule_clear` |
| ready -> published | `promote_scheduled_tick`, every minute |
| any -> published | `schedule_link_post`, when Compose publishes straight into a slot's key |

`payload` is `{ post: <create_post arguments by name>, composer: <opaque editor state> }`. The database only reads `post`; `composer` lets the form reopen where it was left.

The calendar is FullCalendar (`@fullcalendar/react`, pinned to 6.x, with the daygrid and luxon plugins; themed by the `.schedule-calendar` block in `globals.css`). `/admin?start=YYYY-MM-DD` opens it on a date; it shows a Monday-to-Sunday week or a month in US Eastern, and draws four kinds of item (styles in `CalendarCards.tsx`, shared with the key): NFL games (`nfl_games`, plain lines; one "N games" line a day in month view), planned slots (`prompts.schedule_range`; dashed when empty or draft, solid with a light edge when ready), and published prompts (`prompt_posts`, any status, full card on the day it locks with a slim reminder on the day it opened when that differs; list-update cards excluded). Planned slots are fetched with `prompts.schedule_range` and places each planned slot on the Eastern day of its `due_at` (its open time). A published prompt is drawn on the day it locks. It also shows `live`, `locked`, `resolved` (and `void`, `removed`), derived from the linked post in `prompts_private.schedule_slot_view`.

## Pre-fill and the weekly cadence

`prompts_private.schedule_prefill()` runs daily (pg_cron) and whenever the calendar loads. It makes each empty slot with its planned post time (`opens_at`) and lock time already set, so the calendar puts it on the day it should be posted. A slot is made while it can still be played (its lock is ahead) and opens within 21 days. All times are US Eastern (noon means 12:00 in New York, EST or EDT).

For an NFL week whose games run Thursday to Monday:

| Kind | Opens | Locks |
| --- | --- | --- |
| `game_pick` | Noon on game day, **primetime games only** (`nfl_games.primetime`) | The game's kickoff |
| `weekly_picks` | Noon the Wednesday before the week's first kickoff | The week's first kickoff |
| `weekly_awards` (about that week's games) | Noon the Tuesday after the week's last game | Noon the next day (Wednesday) |
| `power_rankings` (the pre-week preview) | Noon the Tuesday before the week's first kickoff | Noon the next day (Wednesday) |
| `bold_predictions` | Noon the day before the week's first Sunday kickoff (the Saturday) | The week's first Sunday kickoff |

A week with no games gets no slots; a week with no Sunday game gets no Bold Predictions slot. The same Tuesday therefore opens both the awards for the week just played and the power rankings for the next one.

### Bold Predictions and the lock time

A Bold Predictions post belongs to the week of the first game at or after its lock (0171). Because this post locks at the first Sunday kickoff, the week's Thursday game is already played at the lock, so a matchup tag must be a game of that week that has **not kicked off at the lock** (0217, `validate_bold_target`). The composer's lock check allows any lock after the previous week's last kickoff and no later than this week's last, and the web and iOS matchup pickers offer only games from the lock on.

## Opening

`prompts_private.promote_scheduled_tick()` finds ready slots whose `opens_at` has passed and calls `create_post` for each in its own subtransaction, with the JWT claims set to the admin who marked it ready (`create_post` checks the caller against the admin list). A slot that fails goes back to `draft` with `publish_error`, so it is flagged on the calendar and not retried every minute.

## Needs attention

A slot needs attention when it is `empty` or `draft`, can still be played (`lock_at` ahead), and is due within 2 days (`due_at` = `opens_at`; pre-filled slots always have one); or when its last attempt to open failed. `attention` names the missing steps.

## Daily email

`prompts_private.schedule_digest_tick()` (pg_cron, 13:00 UTC, about 8 or 9am Eastern) calls the `send-schedule-digest` Edge Function when anything needs attention. The function gets recipients (every row in `prompts_private.admin_config`) and the items from `public.claim_schedule_digest()` (service role only), and sends one email through Resend. No attention items, no email. Same pattern as `send-push`: the database calls out, a shared secret authenticates it, and until it is configured the tick does nothing.

### One-time setup (production)

1. Verify a sender domain in Resend and create an API key.
2. Deploy the function and set its secrets:
   `supabase functions deploy send-schedule-digest` and
   `supabase secrets set DIGEST_FUNCTION_SECRET=… RESEND_API_KEY=… DIGEST_FROM="Ball Party <admin@your-domain>" ADMIN_URL=https://…/admin`
3. Store the URL and the same secret in Vault, under the names the tick reads:
   `select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/send-schedule-digest', 'digest_function_url');`
   `select vault.create_secret('<DIGEST_FUNCTION_SECRET>', 'digest_function_secret');`

## Time zones

`opens_at` and `lock_at` are `timestamptz`. The calendar and the email show US Eastern. The composer's date fields use the browser's own zone, as the lock field always has.

## Not in scope

Recurring templates or generated prompt text, auto-publishing without a ready mark, push or in-app nudges, iOS.
