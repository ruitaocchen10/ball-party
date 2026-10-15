# Ranking lists

Status: **backend built (migrations 0210 to 0213) and the web client built (Lists tab, editor, history, profile tab, home Lists pill and update card). iOS and the prompt prefill are not built.** Each player keeps a living, versioned ranking per list kind (team power rankings, top QBs, and so on). Prompts nudge people to update their lists. Every saved version stays in the player's visible history, so a list's evolution is an honest record.

Jira: BPP-23 (story), BPP-24 (position-list prompts, follow-up).

## Rules

- **Prompts are scheduled nudges.** A ranking prompt opens pre-filled with the player's current list. Submitting it writes a new list version. Power Rankings fire weekly; position-list prompts (QB, RB, WR...) fire less often. Cadence belongs to the prompt, not the list.
- **One card per published version.** A prompt answer is one card, the prompt's own take card (public, like every Huddle card), and it also saves a list version. An edit outside a prompt gets a standalone update card only if the player publishes it, and update cards are friends-only.
- **Every saved version is visible in history, published or not.** There are no private drafts on the record; unsaved reordering lives in the client.
- **Edit cap: one saved edit per list per rolling 24 hours.** Prompt answers are exempt, so a player can save once and also answer the prompt the same day. A save within 10 minutes of the last edit replaces that version (typo grace), unless its update card already has a reply.
- **A prompt's window is the draft.** Resubmitting an open prompt overwrites the player's version for that prompt. At lock it is never touched again; the lock is the commitment.
- **While a prompt for a list kind is open, that list is edited through the prompt.** A standalone save raises `prompt_open` (with the prompt's post id in `detail`), and the client sends the player to the prompt. "Open" means `status = 'open' and now() < lock_at`: opinion posts are never flipped to `locked`, so a past `lock_at` with `status = 'open'` is a closed prompt.
- **Saving a list identical to the current one raises `no_change`**, so it cannot burn the cap.

## Item identity

`prompt_slot_options` rows belong to one post's slot, so their ids differ every week. `feed.ts` already works around this by comparing power rankings through `team_code`. A list outlives any prompt, so its items are keyed by `team_code` (teams) or `player_id` (players, from `prompts_private.nfl_players`). Valid team codes are `private.nfl_team_codes()`, the 32 nflverse codes the Power Rankings options use.

## Tables (all `public`; writes only through the RPCs)

- `ranking_list_kinds`: seeded config. `id` (`power_rankings`, `qb`, `rb`, `wr`, `te`), `label`, `item_kind` (`team` or `player`), `player_position`, and `sizes`, the allowed lengths (`{5,10,32}` for power rankings, `{10}` for positions, top 10 only for now). Adding a kind is an insert. Readable by everyone.
- `ranking_lists`: one per player per kind (`unique (profile_id, kind)`), with `current_version_id`.
- `ranking_list_versions`: append-only, numbered per list. `source` (`edit` or `prompt`), `post_id` (the prompt, unique per list), `update_post_id` (the update card, once published), `note` (at most 280 characters), `created_at`, and `updated_at`, which moves only when a version is replaced (grace window or open prompt).
- `ranking_list_items`: `(version_id, place)` with `team_code` or `player_id`, exactly one of the two.
- `prompt_posts.ranking_kind`: the list kind a prompt feeds. A trigger sets it to `power_rankings` for every Power Rankings post. A position-list prompt will name its own kind.

The list tables are RLS-enabled with owner-only `select` and no write grants. Everyone else reads through the RPCs, so privacy lives in one place.

## RPCs

| RPC | Does |
| --- | --- |
| `save_ranking_list(p_kind, p_items text[], p_note, p_publish)` | The editor's write. `p_items` is the ordered team codes or player ids. Validates the length, repeats and that every item is real and of the right position. Raises `prompt_open`, `no_change`, `edit_limit` (with when the next save opens in `detail`) or `note_too_long`. Replaces inside the grace window, otherwise adds a version. With `p_publish`, creates the update card. Returns the version id. |
| `prompts.submit_response` (extended) | For a post with `ranking_kind`, also writes or overwrites the player's `source = 'prompt'` version in the same transaction. `prompt_responses` is untouched, so consensus, "matched N of 5" and points keep working. No edit cap. |
| `get_ranking_lists(p_username)` | The player's lists: the current version of each kind, with its version count. |
| `get_ranking_list(p_username, p_kind)` | One list's whole history, newest first. The note and update card are shown only to the owner and their friends. |
| `ranking_players(p_ids)` | Names, positions, teams and headshots for the player ids in lists (identity fields only, signed-in callers). Teams need no lookup. |
| `friend_list_updates(p_limit, p_before, p_post_id)` | The viewer's and their friends' published edits, newest first, each with the list it replaced so a card can show what moved. With `p_post_id`, one card if the viewer may see it. |
| `ranking_list_prefill(p_post_id)` | The viewer's current list mapped onto the prompt's options by `team_code` / `player_id`, so the ballot opens pre-filled. No rows when the prompt is not a ranking prompt or the viewer has no list. |

The two reads follow `get_profile` (migration 0186): an unknown, guest or deleted player, a player who blocked the viewer, and a private profile viewed by a non-friend all return no rows. Guests cannot save or read (`not_authenticated`).

## The update card

Publishing an edit creates a `prompt_posts` row (`template_kind = 'ranking_update'`, `status = 'locked'`, `is_opinion`, `ranking_kind` set, author = the player) plus the player's take, whose body is the note. This reuses the thread, reply notifications (0204) and sharing instead of adding a second thread system. Friends-only is enforced in the database:

- The `prompt_posts` read policy shows a `ranking_update` row only to its author and their friends (`public.can_see_ranking_update`, a public function because signed-out reads cannot call into the `private` schema). The `prompt_comments` read policy now shows a comment only when its post is visible.
- `prompts.post_comment` treats a card the caller cannot see as not found.
- Web: `fetchPromptFeed` leaves `ranking_update` posts out, so they never reach the prompt feed or the Takes history, and the sitemap only lists the allow-listed kinds. The home feed reads them through `friend_list_updates` (0213), which returns each card with the list it replaced, and renders a diff, not the full list. The iOS feed asks only for the prompt kinds it renders (`PromptPost.feedKinds`), so update cards never reach it until it is built.

## Migration and backfill

0212 turns every existing Power Rankings response into a `source = 'prompt'` version, oldest post first, with the response's own timestamp, through `private.ranking_backfill_power_rankings()`. It is idempotent, skips deleted accounts, and `supabase/seed.sql` calls it so locally seeded responses get versions too. Dry run against production before deploy: 3 responses from 1 player become 3 versions, 96 items, no invalid or repeated teams.

## Not in this model (yet)

- **Scoring** lists against outcomes. The model supports it (stable item identity, immutable timestamped versions), but no rule is defined.
- **Live consensus** from everyone's current versions, and **compare with a friend** ("you agree on 6 of 10").
- **Custom lists.** Kinds are seeded config, so adding one is an insert, but the UI assumes the fixed set.

## Open questions

1. **Position-list prompts** need a player pool per position. The existing `playerSearch` slot shape picks one player; a ranked player slot does not exist yet (BPP-24). `ranking_list_prefill` can only map players the prompt already has an option for.
2. **Timezone.** The cap is a rolling 24 hours to avoid timezone logic. If "once per calendar day" is wanted, it needs the player's timezone.
3. **Several open prompts of one kind.** Nothing prevents it. `prompt_open` blocks standalone edits while any is open, and each prompt keeps its own version.
4. **Parity.** Both clients need the Rankings profile section, the editor and the new card. Add `features.yaml` entries (and tickets for any gap) in the first change that ships.
