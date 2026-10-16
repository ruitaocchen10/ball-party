# Design system (web)

How the web app (`webapp/`) is put together visually: the tokens, the page layouts, and the shared components. Read this before any UI work. The point is that a new screen is assembled from the kit, not styled from scratch.

The kit lives in `webapp/components/foundation/ui-kit/`. The tokens live in `webapp/app/globals.css`.

## Principles

1. **Use the kit before writing markup.** If there is a component for it, use it.
2. **A second use is a promotion.** When a pattern appears a second time, move it into the kit instead of copying it.
3. **No literals in components.** No hex colors, no raw `text-[Npx]` sizes, no bare `rounded` (use `rounded-card` or `rounded-chip`). Use a token or a kit class. A literal that has to stay (a team-color gradient, a share-card canvas that is exported as an image) gets a comment saying why.
4. **Red means concealed.** Anything one player knows and another doesn't is red, and it turns the normal text color when revealed. Don't use red for anything else, with one exception: error text, which reuses `hidden-text` rather than adding a second alarm color.
5. **Dark only.** There is no light variant. Panels are raised dark surfaces, a step lighter than the background, so what matters goes on a panel and everything else is background.

## Tokens

### Colors

Each is a Tailwind color (`bg-panel`, `text-fg-muted`, `border-line`, …) backed by a CSS variable.

**iOS has its own copy.** `ios/BallParty/Foundation/UIKit/Theme.swift` holds the same colors under camelCase names (`panel-soft` is `panelSoft`). The two files are separate, so each app builds on its own, but `tokens.test.ts` fails if a color differs or exists on only one side. Change a color in both. `/admin/design` (admin only) shows every token as it renders.

| Token | Use |
| --- | --- |
| `surface` | The page background. Also a field's fill on the background. |
| `surface-raised` | Inset wells: inputs inside a raised surface, bid bars, dialogs, empty states. |
| `fg`, `fg-muted` | Text on the background, and its secondary text. |
| `line` | Borders and rules on the background. |
| `panel` | The raised surface: cards, menus, chips. |
| `panel-shade` | A subdued band inside a panel. Also a field's fill on a panel. |
| `panel-fg`, `panel-muted`, `panel-soft` | Text on a panel: primary, secondary, and body copy. |
| `panel-line` | Borders and rules on a panel. |
| `panel-hover`, `panel-ink-hover` | Hover fills for a pressable panel and an ink button. |
| `hidden` | Concealed values and unfilled spots, as a surface. |
| `hidden-text` | The same red, lifted to stay legible on the background. Also error text. |
| `hidden-ink` | The same red, darkened: a hovered or pressed red surface. |
| `grade-elite/strong/even/rough` | Revealed grades and verdicts (QB Season Builder, the Huddle). Deliberately not red. |
| `ball` | A ball given to a take (the football in the take reaction control). Leather orange, never red. |

A selected pill, tab or option is filled `hidden` red with `fg` text; a primary button is a `fg` fill with `surface` text.

Pick the text color by what it sits on: `fg*` on the background, `panel-*` on a panel, `hidden-text` on the background but `hidden-ink` on a panel.

### Type

| Font | Class | Use |
| --- | --- | --- |
| Bebas Neue | `font-slab` | Headings, button labels, big numbers. Usually uppercase. |
| Barlow | `font-sans` | Body text. The default. |
| JetBrains Mono | `font-mono` | Labels, metadata, codes, tabular numbers. |

The small mono uppercase label has three sizes, each a single class that sets font, size, tracking and case. Add color and weight at the call site.

| Class | Size | Use |
| --- | --- | --- |
| `type-label-xs` | 9px | Chips and dense metadata. |
| `type-label` | 10px | Section labels, eyebrows, most small print. |
| `type-label-lg` | 11px | Labels that need a little more presence, and `Button size="sm"`. |

Don't write `font-mono text-[10px] tracking-[…] uppercase` by hand.

### Shape and depth

- **Corners are rounded in two tiers.** `rounded-card` is 8px (`Theme.cardRadius` on iOS): cards, buttons, inputs, selects, menus, modals, wells, and player photos. `rounded-chip` is 4px (`Theme.chipRadius`): badges, banners, and small things nested inside a card. A small player photo takes the chip corner.
- **Round on purpose.** `rounded-full` (`Circle`, `Capsule` on iOS) is only for things that are actually round: user avatars, dots, pill tabs, meters. Don't mix a pill and an 8px control in the same row.
- `shadow-card` (with `shadow-card-hover` for a pressable one) is for raised panels, which read as lit objects.
- `shadow-well` is for passive surfaces: a notice, an empty state, a static container. Don't put it on anything interactive, since a control's border carries its state.
- `shadow-concealed` is for red concealed surfaces.

## Page layout

Every page renders its `<main>` through `PageShell`. It owns width, gutters and vertical padding, so a page never specifies them.

| Variant | For | Shape |
| --- | --- | --- |
| `dashboard` | App workspaces: Home, Party, Solo, Profile, Settings, prompt pages, solo results | Wide and centered (`app-page`: max 80rem), with room for the top bar. Children go in one 760px column (`app-column`); an optional `rail` sits beside it from `xl`. |
| `form` | Sign-in, sign-up, and short single-purpose screens (`size="md"` for a roomier one) | One centered column, full height. |
| `narrow` | A game's waiting, setup and results screens | A readable `max-w-2xl` column of stacked sections. |
| `prose` | Privacy, Support | Long-form text in a reading column. |
| `game` | The play surface. `locked` fits the viewport with no page scroll (in-match); unlocked scrolls and keeps roomier gutters (the lobby) | Full width. |

The sidebar is not part of `PageShell`. When a `Sidebar` is mounted, `globals.css` pads `body`, so every variant centers correctly beside it.

A dashboard page is always the same stack:

```tsx
<>
  <Sidebar displayName={…} email={…} avatarUrl={…} />
  <DashboardHeader displayName={…} email={…} avatarUrl={…} />
  <PageShell variant="dashboard" rail={<QuickActions … />}>
    <PageHeader eyebrow="Solo" title="Play on your own" description="…" />
    {/* content */}
  </PageShell>
</>
```

The shell puts its children in a single 760px column, so a page never sets its own width: the `PageHeader` divider and the content under it can't drift apart. Don't add `max-w-*` wrappers inside a dashboard page. `rail` is optional. From `xl` the column and the 18rem rail are centered together; below that the rail stacks under the column, and a rail that should disappear there hides itself (`hidden xl:block`). The column width is defined once, in `globals.css` (`.app-column` and `.app-layout`).

`PageHeader` has no width of its own and takes the shell's. The admin pages (`/admin/*`) are the one exception: they are an internal tool with their own layout.

## Components

**Actions**

| I need | Use |
| --- | --- |
| A button | `Button`. `variant`: `solid` (light fill, the one primary per view), `ghost` (subordinate), `ink` (a light fill on a panel), `text` (no surface: Cancel, Back), `danger` (destructive, kept quiet). `size`: `md` (default) or `sm` (compact mono, for card and dialog footers). Full width by default; pass `fullWidth={false}` to sit inline. |
| A button that navigates | `ButtonLink`. Same variants and sizes. A `<button>` inside an `<a>` is invalid. |

**Forms**

| I need | Use |
| --- | --- |
| A text field | `Input` / `Textarea`. `variant`: `dark` (on the background, default), `well` (inset in a raised surface), `panel` (on a card). |
| A label, hint and error around it | `Field`. It wraps the control in a `<label>`, so no `id` pairing is needed. |
| A dropdown | `Select`, not `<select>`: the native popup can't be themed. `variant`: `panel` or `dark`. |
| A status or error line under a form | `AnimatedMessage` (`role="alert"` or `"status"`). |
| The `?error=` banner after a redirect | `ErrorBanner`. |

**Surfaces and overlays**

| I need | Use |
| --- | --- |
| A panel with a title and stats | `Card`, with `CardTitle`, `CardMeta`, `CardStats` and `Stat`. A raised dark surface with a hairline edge. `tone="light"` is the `fg` cream with `surface` text, for the people in a room (a taken seat) against dark surfaces around them. |
| A dialog | `Modal` with a `ModalTitle` (its accessible name). Escape and overlay-click close it, focus is trapped and returned, and scroll is locked. `initialFocusRef` sets the first focus. |
| An empty list or feed | `EmptyState`. |
| A small tag ("You", "Locked") | `Badge`. `tone`: `solid`, `soft`, `muted`, `outline`, `success`, `hidden` (red, concealed things only), `ink` (a dark chip for a light card), `scrim` (a dark blurred chip for sitting on top of art, like a prompt card's timer). `size`: `sm` or `xs`. |
| A page heading | `PageHeader` (title, optional eyebrow, description, and back link). |
| A secondary side panel on a dashboard | `DashboardRail`. |

**Concealed information and games**

| I need | Use |
| --- | --- |
| Hidden information | `Concealed`. `label` is required, since hidden things must still announce that they exist. `compact` for a chip-sized one. |
| The hidden → revealed swap | `Reveal`. |
| A match's turn or lot strip | `MatchStrip` and `StripCell`. |
| A slot-machine reel | `SlotReel`. |
| A team logo | `TeamLogo`. |
| A floating list under a field | `AnchoredList` (portaled, so clipped cards don't crop it). |
| An expand/collapse affordance | `Chevron`. |
| Underlined tabs that switch a page's sections (profile sections, leaderboard boards) | `TabBar`: link-based, the page owns the active one. iOS has the same `TabBar`; the leaderboard pins it directly under the navigation bar. |

App chrome (`Sidebar`, `AccountMenu`, `BrandMark`, `MotionProvider`) is also in the kit, but pages don't compose it directly beyond the dashboard stack above.

### Raw elements that are fine

Some controls are deliberately not kit components, because they are a different control and not an unconverted button or input:

- Sidebar navigation items and the sidebar collapse toggle.
- Segmented and toggle controls, and picker tiles (`SlotFaces`, `PromptTiles`, `MatchupPicker`).
- Icon-only buttons.
- Comboboxes and search fields (`PlayerPicker`, `HuddleSearchField`) and the join-code field.
- The inline composers (`TakeComposer`, `TakeReplyComposer`) and the auction bid input, which have their own sizing.
- `hidden`, `radio`, `checkbox` and `file` inputs.

If you reach for a raw `<button>` or `<input>` outside this list, check the kit first.

## Patterns

**A form.** Fields in `Field`, errors in `AnimatedMessage`, one `solid` button.

```tsx
<form action={action} className="flex flex-col gap-3">
  <Field label="Email">
    <Input name="email" type="email" required autoComplete="email" />
  </Field>
  <AnimatedMessage role="alert" className="text-sm text-hidden-text">{state.error}</AnimatedMessage>
  <Button type="submit">Save</Button>
</form>
```

**A dialog.** Mount it while it should be open, and give it a title.

```tsx
{open ? (
  <Modal onClose={() => setOpen(false)} closeLabel="Close feedback" initialFocusRef={firstField}>
    <ModalTitle className="font-slab text-3xl uppercase">Help shape the game</ModalTitle>
    …
  </Modal>
) : null}
```

**A destructive action.** `Button variant="danger" size="sm"`, behind a confirm step. Keep it visually subordinate, with a `solid` button as the safe choice nearby.

**An empty list.** `EmptyState` with a title and one sentence saying what will appear and when.

## Adding to the kit

- Put it in `webapp/components/foundation/ui-kit/` and add a `Name.test.tsx` beside it. Every kit component has one.
- Add `"use client"` only if it needs it: state, effects, or a client-only library.
- Name variants for meaning (`danger`), not appearance (`red`).
- Document the *why* in a comment, the way `Button` and `Card` do: what rule the component enforces.
- Then add a row to the catalog above.

## Known gaps

The kit isn't finished. These are known, not endorsed:

- **The type scale covers labels only.** Body, caption and display sizes (and some `text-xs` labels) are still raw `text-[Npx]` classes.
- **Settings' cards are narrower than its `PageHeader`.** Content widths inside a page are not yet standardized.
- **A few small buttons are still hand-styled**, such as the join-room code button and the share-card headline fields.
- **Game screens are unreviewed in a live match** since the move to `PageShell`; their paddings were unified (`narrow`, `game`).
- **Nothing enforces any of this yet.** It is held up by review. Lint rules for raw buttons, hex colors and `text-[Npx]` are the next step.
