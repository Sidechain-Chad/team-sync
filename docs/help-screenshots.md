# Help centre screenshots

How to retake any of these identically. All captured from the seeded
development database (`bin/rails db:seed`), viewport 1440x900, no scroll.

| File | Route | Seeded record | Theme set via |
|---|---|---|---|
| `board-light.jpg` / `board-dark.jpg` | `/boards/1` | Board #1, "Product Launch" | `User.find_by(email: "demo@example.com").update!(theme: "light"` or `"dark")` |
| `card-modal-light.jpg` / `card-modal-dark.jpg` | `/cards/11` | Card #11, "Book the launch venue" (on the Product Launch board) | same |
| `planner-light.jpg` / `planner-dark.jpg` | `/planner` | No specific record; renders the current month for whichever user is signed in | same |

Steps used:

1. `bin/rails db:seed` for a clean, known dataset.
2. Set the demo user's theme in the database directly (not through the UI),
   so the very first server-rendered response already carries the right
   `data-theme`, rather than a client-side toggle that might not match what
   a real signed-in visitor sees.
3. Sign in as `demo@example.com` and visit the route above.
4. Screenshot the viewport, no cropping.
5. `convert original.png -resize 1100x -quality 82 output.jpg` to keep the
   pair for one screen under roughly 100KB combined.
6. Set the theme back to `"light"` afterward — screenshots should never be
   the reason a seeded account is left in a non-default state.

Images live in `public/help-images/`, served as plain static files rather
than through the asset pipeline, since the markdown articles reference them
with a literal `<img src="...">` and have no access to Rails' `asset_path`.
