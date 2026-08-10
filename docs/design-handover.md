# TeamSync — Design Handover

This document exists to brief an external design pass on TeamSync, a Trello-style
kanban app. Section 0 is a set of ready-to-paste prompts for Google Stitch.
Everything after it (sections 1–7) is reference material for us — the product and
implementation context needed to turn whatever Stitch proposes into something we
can actually build and ship in this codebase.

---

## 0. Paste-ready prompts for Google Stitch

Four prompts, one screen each. Paste one at a time — Stitch designs a screen, not
a whole app. Each is self-contained: what the app is, the one screen in question,
the visual direction, and the elements that must survive the redesign. None of
them use implementation words (no "Turbo," "Stimulus," "frame," or token names) —
those constraints live in sections 3–5, for us, not for the design tool.

To adapt any of these to a screen not covered below (the board's settings page,
the archive view, the notifications panel), keep the opening two sentences and the
"Visual direction" paragraph as-is, and swap only the "Screen" and "Must keep"
lists for the new screen — the elements can be pulled straight out of section 2.

### Prompt 1 — Board view

> Design the main working screen of TeamSync, a project board app used by small
> teams to plan and track work together, similar in spirit to Trello. This is the
> screen people spend most of their time on: a single board made of several
> vertical columns ("lists"), each holding a stack of task cards, all scrolling
> horizontally across the screen. Cards can be dragged between columns.
>
> Screen: the board view. A top bar shows the board's name, the small circular
> photos of the people on the board, and a couple of icon buttons (search, notify,
> a share action). Below it, columns run left to right, each with a header (list
> name, a card count, a small overflow menu) and a vertical stack of cards. Each
> card is a compact block showing: one or more small colored label pills, a short
> title, a due-date chip, small icon indicators for comments/attachments/checklist
> progress, and a row of small circular member photos. Each column ends with an
> "add a card" affordance; the row of columns ends with an "add a list" affordance.
> A soft, muted background (a photo or a generated gradient wash) sits behind the
> whole canvas, with the columns and cards as solid panels on top of it — so
> whatever you design for the cards and columns needs to stay legible over a
> busy or brightly-colored backdrop, not just a plain background.
>
> Visual direction: warm and human, not corporate-cold. Think "Golden Hour" — warm
> cream and espresso neutrals, with a persimmon/coral accent color used sparingly
> for the important actions and highlights (roughly `#BE451A`, ranging toward a
> brighter `#EE5B2B`). Avoid stark pure white or cold blue-grey. Typography should
> feel a little editorial for headings, plain and readable for body text.
>
> Keep: the horizontal multi-column layout, the card's internal element list
> above, the legible-over-any-background requirement, and a visible drag
> affordance on cards.

### Prompt 2 — Card modal (the detail view)

> Design the detail view for a single task card in TeamSync, a project board app
> for small teams (similar in spirit to Trello). This view opens as a large
> overlay/panel when someone clicks a card, and it is the densest, most
> information-heavy screen in the whole app — the redesign that matters most.
>
> Screen: the card detail overlay. At the top: the card's title (editable in
> place) and a way to mark it complete. Below that, a row of small controls for:
> which column the card currently lives in (with a way to move it), who is
> assigned (small circular member photos plus an add button), colored label pills
> (plus an add button), and a due-date chip (plus a way to edit it). A quick-add
> row offers checklist / location / attachment shortcuts. Below that: a rich-text
> description field; one or more checklists, each with a progress bar and a list
> of checkable items; a list of file attachments with thumbnails; an
> optional location block with a small static map and address. A three-dot menu
> gives access to duplicating or archiving the card. Down the side (or below, on
> narrower screens): a running feed of comments and activity log entries, with a
> comment box pinned near it.
>
> Visual direction: same warm "Golden Hour" palette as the rest of the app —
> warm cream/espresso neutrals, sparing use of a persimmon/coral accent
> (`#BE451A`) for primary actions, a separate warm leaf-green for
> completion/success states (not the same color as the accent). The core design
> problem to solve is hierarchy: there are ten-plus distinct sections stacked in
> one view, and today they read as a flat list. Give them real visual grouping,
> breathing room, and a clear reading order, without hiding any of them behind
> extra clicks.
>
> Keep: every section named above must remain visible/reachable on this one
> screen (no combining sections into a different screen or removing any of
> them), and the two-zone layout (task details vs. comment/activity feed).

### Prompt 3 — Boards index (home screen)

> Design the home/landing screen for TeamSync, a project board app for small
> teams (similar in spirit to Trello). This is the first screen a person sees
> after signing in — a browsable list of every board they have access to.
>
> Screen: the boards home screen. A left-hand sidebar (or top section on mobile)
> offers navigation to this screen, a calendar-style planner, and a "closed
> boards" archive. The main area is organized into a few grouped sections: a
> short horizontal strip of recently-viewed boards, a "starred" section for
> favorites, a "your boards" grid, and a separate grid for boards shared with the
> person by other teams. Each board is shown as a colorful rectangular tile — a
> photo or a colorful gradient — with the board's name and last-updated time
> overlaid, plus a small star toggle. There's a clear, prominent way to create a
> new board.
>
> Visual direction: warm "Golden Hour" palette — cream and espresso neutrals, a
> persimmon/coral accent (`#BE451A`) used only for the primary action (creating a
> board) and small highlights, not as a dominant color. The board tiles themselves
> carry their own varied colors/photos and should read as the most visually rich
> part of this screen — everything else (nav, section headers, empty states)
> should be calmer so the tiles stand out.
>
> Keep: the sectioned grid structure (recent / starred / yours / shared), the
> tile-with-cover-image format for each board, and a visible create-board action.

### Prompt 4 — Planner (calendar view)

> Design a monthly planner screen for TeamSync, a project board app for small
> teams (similar in spirit to Trello). This screen pulls together every task with
> a due date, across all of a person's boards, into one calendar.
>
> Screen: the planner. A header shows the current month, previous/next month
> arrows, a "today" shortcut, and a toggle to switch between this calendar layout
> and a map layout (showing the same tasks by location instead). Below that: a
> standard seven-column, multi-week month grid. Each day cell shows its date
> number and a small stack of colored task chips — short, single-line, color-coded
> to match each task's label. A task that spans several days should read as one
> continuous colored bar across those days' cells, not as a repeated chip in each
> one.
>
> Visual direction: warm "Golden Hour" palette — cream and espresso neutrals, the
> persimmon/coral accent (`#BE451A`) reserved for the "today" highlight and
> primary controls. The grid itself should feel calm and legible even when
> several days are packed with colored chips; today's date cell should be
> unmistakable at a glance.
>
> Keep: the month-grid (not a list/agenda) layout, multi-day tasks rendered as
> continuous spanning bars, and the calendar/map toggle in the header.

---

## 1. What the product is

TeamSync is a Trello-style kanban board app: boards contain lists, lists contain
cards, and teams organize and track work by moving cards across lists. It supports
real-time collaboration — when one person moves a card, adds a comment, or
completes a checklist item, everyone else looking at that board sees it update
live, without reloading. Cards carry due dates, labels, checklists, attachments,
members, and optional locations, and there's a cross-board calendar/map planner
for anything with a due date.

Audience, honestly: this is built for small teams (a handful of people sharing a
handful of boards), not an enterprise tool. It is currently a single-developer
project — there is no dedicated design function, which is the whole reason for
this handover.

---

## 2. Screen inventory

Every screen a signed-in user can reach, grouped by area. Routes are relative;
all board/card/list routes are scoped to the current user's accessible boards.

### Boards

| Screen | Route | Purpose | Key UI |
|---|---|---|---|
| Boards index (home) | `GET /` | Landing page listing every board the user can reach | Sidebar nav; recently-viewed strip; starred grid; "created by me" grid with a create-board tile; shared-boards grid; each board a cover tile (photo or gradient) with name, "updated x ago," star toggle, watch indicator |
| Board view | `GET /boards/:id` | The core working screen — lists and cards on one board | Full-bleed photo/gradient background; header with board-name dropdown (edit, members, activity, archive, watch, copy, close/delete), filter popover, member avatars, share; horizontally-scrolling lists, each with a header dropdown (sort, WIP limit, copy, archive-all) and draggable cards; "add a card"/"add a list" affordances; keyboard-shortcut overlay |
| Board map | `GET /boards/:id/map` | Map of this board's cards that have a location | Full-bleed Mapbox map with one marker per located card; server-rendered empty state if none |
| Board activity | `GET /boards/:id/activity` | Chronological feed of everything that happened on the board | Merged activity + comment rows, paginated "load more," empty state |
| Board archive | `GET /boards/:id/archive` | Recover archived cards | List of archived-card rows (labels, title, source list, age, member count) with restore/delete |
| Closed boards | `GET /boards/closed` | Recover closed boards | Deliberately minimal list of closed boards with reopen (owner-only) |
| Board settings | `GET /boards/:id/edit` | Rename a board, manage its cover/background, manage members | Single narrow form: name, avatar upload, background upload, delete link; separate members section with email-invite form and member rows |
| Board switcher | `GET /switch_boards` | Quick "jump to another board" overlay | Modal with "your boards" / "shared with you" cover-tile grids; a *second*, simpler text-link version of this same idea also exists as a dropdown popover in the top nav (see §2 note below) |

### Planner (cross-board, due-date driven)

| Screen | Route | Purpose | Key UI |
|---|---|---|---|
| Planner (calendar) | `GET /planner` | Month-grid view of every card with a due date, across all boards | 7-column month grid; multi-day cards render as a spanning bar, not a repeated chip; month nav, calendar/map toggle |
| Planner panel | `GET /planner/panel` | Compact agenda drawer, opened from the board view's bottom nav | Day-grouped agenda list (Today/Tomorrow/weekday), each entry a colored-stripe row with title, board name, start/due label, location |
| Planner map | `GET /planner/map` | Same idea as board map, but across every board, filtered to the current month | Full map, "N cards with location" pill, markers labeled "Board · due date" |

### Card modal

| Screen | Route | Purpose |
|---|---|---|
| Card detail | `GET /cards/:id` | The single-card detail overlay — see below |

This is the densest surface in the app and the one a redesign lives or dies on.
Current sections, top to bottom:

- **Header row**: a chip showing which list the card is in, which opens a
  popover to move it to another list/position; a watch (eye) toggle; a **···**
  menu; a close button. *Note: the ··· menu today holds only "Copy card" and
  "Archive card" — move and watch are their own separate header controls, not
  inside that menu. A redesign is free to group all four under one menu (that's
  arguably cleaner), but should know that's a change from what exists today,
  not a like-for-like visual pass.*
- **Title + completion toggle** — title is editable in place.
- **Quick-add row** — three buttons: add checklist, add location, add
  attachment.
- **Members** — avatar row plus an add-member picker (assigned vs. unassigned
  board members).
- **Labels** — colored pill row plus an add-label picker (toggle existing,
  inline-edit a label's name/color, or create a new one).
- **Due date** — a pill (color-coded by how close/overdue) plus a form with
  quick presets, an optional start date, and a "mark complete" checkbox.
- **Description** — rich text (bold/italic/headings/lists/links/images/code
  blocks/quotes/dividers), read mode vs. a full toolbar edit mode.
- **Location** (if set) — a static map image, name/address, remove control.
- **Attachments** (if any) — thumbnail or file-icon rows with download/delete.
- **Checklists** — one or more, each with a title, delete, progress bar, and a
  list of checkable items with an "add item" field.
- **Comments and activity** — one interleaved, newest-first feed (comments
  removable by their author) plus a mention-aware comment composer, with a
  "hide details" toggle to collapse everything above it.

That's ten-plus distinct sections in one view. The header row alone stacks five
popover-triggering controls in under 150px of height; the description's rich-text
toolbar is the single densest control on the screen (seven groups, five of which
open their own sub-menus).

### Account

| Screen | Route | Purpose | Key UI |
|---|---|---|---|
| Profile | `GET /account/profile` | Edit name/avatar | Avatar upload, name form |
| Activity | `GET /account/activity` | Personal activity feed | Feed of the user's own recent actions, empty state |
| My cards | `GET /account/cards` | Every card the user is a member of, across boards | Sortable (due/updated) table, responsive stacked-row fallback |
| Settings | `GET /account/settings` | Notification preferences, theme, deactivation | Per-notification-type checkboxes, link to Devise security settings, danger-zone deactivate |

### Notifications & search (top-nav dropdowns, not full pages)

- **Notifications** (`GET /notifications`) — lazily-loaded panel in the bell
  dropdown; unread dot per item, "mark all read," empty state; a small
  always-visible unread-count badge sits on the bell icon itself.
- **Search** (`GET /search`) — dropdown from the top-nav search field; shows
  recent boards by default, or highlighted board/card matches once typing.

### Auth (Devise)

`sign_in`, `sign_up`, account-security edit, password reset request, password
reset form — all share one restyled "auth card" treatment (gradient background,
centered card, TeamSync wordmark). **Email-confirmation and account-unlock pages
are still bare, unstyled Devise scaffolding** — no Tailwind classes at all, in
sharp contrast to every other screen in the app (see §7).

**Where design attention is most and least uneven:** the board view, the top/
bottom nav, the boards index, and the planner are the most polished — layered
empty states, hover affordances, responsive fallbacks, keyboard shortcuts. Board
settings (`/boards/:id/edit`) and the closed-boards/archive recovery pages are
functional but plain "form-in-a-box" or "list-of-rows" treatments by comparison.
The Devise confirmation/unlock pages have had no design attention at all.

---

## 3. Current visual language — "Golden Hour"

The existing system is a warm, editorial palette (cream/espresso neutrals with a
persimmon/coral accent), fully tokenized so both a light and a dark mode exist
from the same design. Below is what we'd defend and what's negotiable.

**We'd defend:** the warmth (no cold blue-greys, no stark pure white/black), the
accent color being genuinely rationed (roughly 10% of any given screen — it's
reserved for primary actions, not decoration), and success (completion) being a
visually distinct color family from the action accent. These are load-bearing
product decisions, not just taste.

**Negotiable:** the exact hues, the specific type pairing, density and spacing
choices, and anything about the current icon set (see §5). If Stitch's design
wants to shift the palette meaningfully, that's a real option — see §5 for what
that costs to implement.

### Token table

Every token below has both a light and dark value today — a new design needs to
supply both, not one design that gets darkened algorithmically later.

| Category | Token | Light | Dark |
|---|---|---|---|
| Brand (accent) | `brand-700` | `#A93B12` | *(fill — pinned, same both themes)* |
| | `brand-600` | `#BE451A` | *(pinned)* |
| | `brand-500` | `#EE5B2B` | *(pinned — icons/accents only, never large fills or body text)* |
| | `brand-400` | `#F9906B` | *(pinned)* |
| | `brand-100` | `#FBE9E0` | `#3A211A` |
| | `brand-fg` | `#BE451A` | `#F9906B` |
| | `brand-fg-hover` | `#A93B12` | `#FCBCA6` |
| Ink (text) | `ink-900` | `#2A211C` | `#FAF6F2` |
| | `ink-700` | `#4A3C33` | `#EDE4DB` |
| | `ink-500` | `#6E5F55` | `#B3A498` |
| | `ink-300` | `#B7A99D` | `#8A7A6D` |
| Surface | `surface-0` | `#FFFFFF` | `#241D18` |
| | `surface-50` | `#FAF6F2` | `#16120F` |
| | `surface-100` | `#F7F1EB` | `#1C1714` |
| | `surface-200` | `#EFE7DF` | `#322822` |
| | `surface-300` | `#E6DACE` | `#40342B` |
| | `surface-muted` | `#FDFBF9` | `#1E1814` |
| Line / hairline | `line` | `#E4D9CF` | `#3A2F27` |
| | `hairline` | `#2A211C` @ 5% | `#FFFFFF` @ 12% |
| Danger | `danger-600` | `#B91C1C` | *(fill, pinned)* |
| | `danger-50` | `#FEE9E7` | `#3A1A1A` |
| | `danger-fg` | `#B91C1C` | `#F0918B` |
| | `danger-fg-muted` | `#C74949` | `#E0736C` |
| | `danger-line` | `#B91C1C` @ 25% | `#F0918B` @ 65% |
| Warn | `warn-700` | `#A94E08` | `#EDB45F` *(foreground-only; no fill counterpart)* |
| | `warn-100` | `#FDEBC8` | `#3A2A12` |
| Success | `success-600` | `#4D7C0F` | *(fill, pinned)* |
| | `success-100` | `#EBF3D8` | `#242E14` |
| | `success-fg` | `#4D7C0F` | `#A9CC63` |
| Nav (never inverts) | `nav-bg` | `#2A211C` | *(same)* |
| | `nav-fg` | `#EFE7DF` | *(same)* |
| | `nav-fg-muted` | `#B7A99D` | *(same)* |
| Scrim (never inverts) | `scrim` | `#2A211C` | *(same)* |
| | `scrim-fg` | `#FAF6F2` | *(same)* |
| Canvas wash | `canvas-golden-stop` | `#F1E6DA` | `#221A15` |

Two structural points worth carrying into any redesign:

- **Fill tokens and `-fg` (foreground) tokens are not interchangeable**, and this
  is arithmetic, not preference: a fill that white text sits on top of and a
  foreground color used on a dark surface need different luminance ranges that
  don't overlap once dark mode exists. `brand-600`, `danger-600`, and
  `success-600` are fills and stay pinned across themes; `brand-fg`,
  `danger-fg`, and `success-fg` are the versions used as text/icon color and are
  the ones that actually lighten in dark mode.
- **Nav and scrim are chrome that stays dark in both themes on purpose** — the
  top/bottom nav bars and image/backdrop overlays never invert, because they're
  not "light surface, dark in dark mode," they're just always-dark chrome.

### Fonts

- **Bricolage Grotesque** — headings: page titles, the card modal title, list
  names, the wordmark.
- **Instrument Sans** — everything else (body text, UI labels, buttons).

Both are loaded from Google Fonts over a CDN link in the page `<head>`, not
self-hosted.

### Dark mode

Dark mode already exists and is live today — it isn't a future project, it's a
constraint on this one. It works by redefining the same token *values* under a
`data-theme="dark"` attribute (and, for "match my system," under a
`prefers-color-scheme: dark` media query), never by swapping which token is used
where. **A new design needs a light and a dark value for every color it
introduces, not a single design that gets auto-darkened afterward** — several
existing tokens (nav, scrim, the `-fg` foregrounds) exist specifically because a
naive "just darken everything" pass produces wrong contrast or inverts things
that shouldn't invert (a nav bar going light in dark mode, for instance).

---

## 4. Interaction patterns a redesign must not break

These are the things that look like a simple visual change but are actually load-bearing plumbing. Get these wrong and a "just a redesign" turns into a rewrite.

- **Server-rendered frames.** The card modal, inline title/description editing,
  the "add a card" composer, and most dropdown panels are rendered by the server
  and swapped into the page in place — they are not client-side-only components
  with local state. A design that assumes an interaction can transition entirely
  in the browser (say, an optimistic multi-step wizard with no server round trip)
  needs a corresponding server response at each step, or it can't be built as
  drawn.
- **Live updates across sessions.** Card moves, list changes, badge counts, and
  comment/activity feeds update in real time for every viewer of a board, via
  server-pushed updates — not polling, not a manual refresh. This has an
  important edge case that already cost real engineering time: anything that is
  *per-viewer* rather than shared (e.g., "does the current viewer watch this
  card") cannot simply be broadcast to everyone looking at the board, or one
  person's private state leaks onto everyone else's screen. A redesign that adds
  new per-user indicators on a shared surface (a board, a list) needs to flag
  that explicitly so it's built the same careful way.
- **Drag and drop.** Cards drag between lists; lists themselves drag to
  reorder. This is a real library-driven interaction, not a mockup affordance —
  any redesign of the card/list shape needs to keep a workable drag handle and
  drop target.
- **The board background is arbitrary.** It's either a photo the user uploaded
  or one of several generated gradients — never a fixed color the designer
  controls. Every panel that floats over that canvas (lists, cards, popovers)
  has to stay legible over unpredictable, possibly busy or bright imagery, not
  just over the sample background in a mock.
- **Keyboard shortcuts and focus.** There's a shortcut-help overlay, single-key
  shortcuts for common actions, and a real focus ring that moves between cards
  on arrow keys. Escape always closes just the topmost thing on screen (the
  shortcut overlay, then a popover, then the card modal) — a redesign that adds
  a new floating layer needs to say where in that stack it belongs.
- **A defined stacking order.** Nav, in-page overlays, dropdown menus, the modal
  and its own popovers, and toast notifications each occupy a specific,
  named layer, in that order, and nothing uses an arbitrary one-off value. If a
  redesign introduces a new kind of floating surface (a side panel, a
  command palette), it needs to say explicitly where it sits in that order —
  "on top" isn't specific enough once there are already six layers.

---

## 5. Hard implementation constraints

These are enforced today by an automated test suite (noted where true) or by
consistent, unbroken convention (noted where not) — either way, a design that
violates them will need rework before it can ship.

- **Zero raw color in views** — no `bg-white`, no Tailwind's stock gray/slate/
  zinc/neutral/stone palette, no hardcoded hex codes anywhere in a view or a
  JS-rendered template. Every color has to resolve through the token system
  above. **Enforced by an automated test.** (One documented, narrow exception:
  the map library needs one literal hex because it can't read a CSS variable.)
- **No inline JavaScript, and in practice only two inline styles exist**: a
  checklist progress-bar width and the board's background-image URL, both of
  which are genuinely per-record dynamic values with nowhere else to live.
  **This is a real, consistently-held convention — verified directly, not a
  single exception found anywhere else in the codebase — but unlike the color
  rule above, there is currently no automated test enforcing it.** (Worth
  adding one; noted here so a designer doesn't assume it's unguarded license.)
- **Every color needs a light and a dark value.** See §3 — enforced by an
  automated test for the existing tokens.
- **Opacity modifiers and shadows can't be themed.** A utility like
  `bg-scrim/60` or any `shadow-*` class gets compiled to a literal color value
  at build time, with no live reference to a token — so it looks identical in
  light and dark mode no matter what the token says. Any design leaning on
  translucency or drop shadows for depth needs to know those specific effects
  are frozen at one value across both themes today, not adjust automatically.
- **44×44px minimum tap targets on icon-only controls.** This is a consistent
  convention throughout the app today — **not currently backed by an automated
  test**, same caveat as above.
- **Icon-only controls need accessible labels, and every dropdown trigger
  carries the pair of ARIA attributes that mark it as an expandable control.**
  Enforced by an automated test. Dropdown panels are plain containers, not a
  formal ARIA menu — several of them contain real form fields (a text input, a
  select), which a strict menu role doesn't allow, so don't design a dropdown
  panel that only makes sense as a list of menu items.
- **Fonts are loaded from Google Fonts over a CDN link, not self-hosted.**
  Adding a new font family is a real but modest cost — one more font family in
  that link, plus a new token — not a large one.
- **Icons are Font Awesome 6, loaded from a public CDN**, used as inline
  `<i>` tag classes throughout every view. Swapping the icon library is
  realistic in principle — it's one link tag — but touches every view file that
  references an icon class, so it's a large, mechanical, easy-to-verify job
  rather than a risky one. A redesign that leans on a specific, distinctive icon
  set should say so explicitly so we can scope that work.

---

## 6. What we want from the redesign

Honest state today: the app works, it's internally coherent, and the palette
reads as warm and intentional — but it was built feature by feature over several
months with no single holistic design pass. It reads as **assembled**, not
**designed**: individually reasonable screens that don't yet feel like one
considered product.

What we're asking for: a stronger, more distinctive visual identity, and better
information hierarchy on the densest screens — the card modal above everything
else — **without** requiring a different interaction model. This is a visual and
layout redesign, not a product-behavior redesign.

**Fixed, not up for negotiation:**
- The information architecture — boards → lists → cards, plus the cross-board
  planner. Not "boards → projects → tasks" or any other reshaping.
- The feature set as it exists today (see the screen inventory, §2).
- The technology underneath — Rails, server-rendered frames, Tailwind. A design
  that requires a fundamentally different client architecture to build isn't
  usable here, however good it looks.

---

## 7. Known rough edges

Worth knowing about going in — solving these is worth more than a design that
ignores them:

- **The planner's calendar grid breaks on narrow phones.** At a 375px-wide
  screen, its seven-column grid divides down to roughly 46px-wide day cells,
  and the task chips inside them truncate to a sliver of text — effectively
  unusable at that width. (A related header-overflow bug on the same screen has
  already been fixed; the grid itself has not.)
- **Shadows don't adapt to dark mode** (see §5) — they're frozen at their light
  design and read as slightly off/flat once the surface around them goes dark.
- **The map always renders in Mapbox's own light street style**, in both light
  and dark mode — there's no dark map style wired up yet, so a map on a dark
  page currently looks visually disconnected from the rest of the UI around it.
- **Native checkboxes are only lightly styled** — the browser's own checkbox
  rendering with a color accent applied, not a fully custom checkbox design.
- **Empty states are inconsistent in polish** — some screens (boards index,
  notifications, the map) have a considered icon-plus-copy empty state; a couple
  of recovery/utility screens are plainer; the two Devise scaffold pages (email
  confirmation, account unlock) have no styling applied at all.

---

*Screenshots were not included in this document (they'd need external hosting)
but can be supplied separately alongside it if useful.*
