# CLAUDE.md — TeamSync

Trello-style kanban app. Rails 7.1 · Hotwire (Turbo + Stimulus) · importmap-rails (NO node build step, no package.json) · Tailwind CSS v4 (CSS-first config) · SortableJS · acts_as_list · Devise · Active Storage on **Cloudinary** (dev + prod; tests use Disk — behavior can differ between them) · minitest.

## Environment gotchas (these WILL bite you)

- **Tailwind watcher does not run here** (no watchman; `bin/rails tailwindcss:watch` exits immediately, and the dev server is usually started bare, not via `bin/dev`). After ANY change that adds/removes utility classes: `bin/rails tailwindcss:build`, then reload. "My CSS change did nothing" almost always means you skipped this.
- **Importmap only.** New JS deps are pinned in `config/importmap.rb` (esm.sh pattern, exact versions — unversioned pins drift). Never `npm install`.
- **Stimulus identifiers are dash-case**: `board_filter_controller.js` registers as `board-filter`. Wiring `data-controller="board_filter"` silently does nothing.
- **Server restart is required** for `config/importmap.rb` changes to take effect.
- Active Job runs on the default `:async` adapter everywhere (no queue backend); jobs are not durable across restarts.

## Playwright / browser verification (there's an MCP configured)

- Playwright's ref-based clicks **intermittently no-op against Stimulus dropdowns and form submits** — no error, nothing happens. Drive them with direct DOM events via `browser_evaluate` instead.
- **SortableJS drags** (`forceFallback: true`) don't respond to `browser_drag` — use raw pointer/mouse event sequences.
- **ProseMirror/tiptap** ignores synthetic selection; drive it through the editor's own command API (`editor.chain().setTextSelection(...)...`), reachable via `window.Stimulus` → controller instance.
- Verify UI work in the browser, not just by tests — this project's history is full of bugs only the browser caught (silently-broken drag persistence, nav overflow at 375px, Stimulus naming no-ops).

## Conventions

- **Authorization = scoped finds.** Every id from params resolves through `current_user.all_boards` / `all_lists` / `all_cards` / `all_checklists` (see `User`), or an association chained off an already-scoped record. Raw `Model.find(params[...])` is a security bug here. Cross-tenant requests must 404 (RecordNotFound), not 403. Foreign keys arriving in params (e.g. `list_id`) are validated through the scope AND confined to the same board — see `CardsController#board_scoped_list`.
- **Board destroy is owner-only** (`current_user.boards`); most other actions are member-level. Match UI visibility to enforcement (`Board#owner?`).
- **Positions are 1-based**; the JS converts from Sortable's 0-based index, the server trusts it verbatim (`newDraggableIndex + 1` → used as-is). Do not add another `+1`. `resolved_move_position` accepts "top"/"bottom"/integers and clamps server-side.
- **Eager loading:** anything rendering many `cards/_card` partials uses `Card::BOARD_PAGE_INCLUDES` / `Card.with_board_page_includes`. `comments_count` is a counter cache — don't re-add `:comments` to board-page includes. In the card partial, count checklist items in Ruby against the loaded association (`count(&:completed?)`), never `.where(...)` — that reintroduces the N+1.
- **Query-count tests** (`count_queries` / `assert_max_queries` in test_helper) pin the N+1 fixes: the real assertion is flat-count-as-data-doubles. If you must raise a ceiling, it must be a fixed cost independent of row count, documented in a comment. Devise adds a session-revalidation query on the second `get` in one test session — use fresh sign-ins per measurement.
- **Named Active Storage variants** (`:cover` 560×200 on Card attachments, `:tile` 400×160 on Board avatar), `preprocessed: true`. Never call `.processed` in a request path. Mapbox markers can't read CSS tokens — the literal hex in `board_map_controller.js` must manually track `--color-brand-600`.

## Design system — "Golden Hour"

- **All chrome colors flow from `@theme` tokens** in `app/assets/tailwind/application.css`: `brand-*` (persimmon/coral — actions only, ~10% of any screen), `ink-*` (espresso text/nav), `surface-*` (warm neutrals), `line`, `danger/warn/success-*`. Zero raw Tailwind grays/blues/reds in views; zero new hardcoded hexes.
- `danger` is crimson and must stay visually distinct from brand persimmon. `success` is for status (checkmarks), brand is for actions — an "Invite" button is brand, a complete-toggle is success.
- Shadows are espresso-tinted app-wide (defined at the tokens); the golden-canvas gradient (`.canvas-golden`) belongs on outermost page wrappers, content sits on it as white cards. Body has a surface-50 floor.
- Fonts: Bricolage Grotesque (`font-display`) for wordmark/page-h1/board/list/card-modal titles; Instrument Sans for everything else.
- Contrast is measured, not eyeballed: white-on-brand-600, brand-600 links, ink-500 secondary, warn pill ≥ 4.5:1. If a token change breaks one, darken the token, never patch per-site.
- A11y baseline (maintain it): aria-labels on icon-only controls, `aria-hidden` on decorative icons, focus-visible rings everywhere, hover-reveals also reveal on `group-focus-within`, `Label::COLORS` and avatar colors are user content — never retheme them.

## Testing & process

- minitest in `test/`, fixtures. Every authorization fix ships with a cross-tenant 404 test. Every N+1 fix ships with a flat-query test, and its detection is proven by temporarily reverting the fix.
- Write the failing test BEFORE fixing a suspected bug; if it passes as-is, stop and report instead of "fixing".
- Full suite must be green before reporting. Don't mix regression fixes and new features in one changeset.
- Filter feature: client-side only (`board_filter_controller.js` reading `data-filter-*` attrs rendered server-side); hidden-class toggling, never DOM removal; re-applies on `turbo:before-stream-render` + `turbo:frame-load`.

## Dev data

Seed login: demo@example.com (password in seeds). Browser QA sessions should clean up any cards/labels/favorites they mutate, or note the artifacts in the report.
