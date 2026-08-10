# Deploying TeamSync to Render

This is the human checklist. `render.yaml` defines the service itself; this is
the ordered set of steps around it that a blueprint sync can't do for you.

## 0. Before you start

Production was 500ing on every page for ~2 months across 23 failed deploys,
while Render reported it healthy the whole time — `/up` (Rails' default health
check) never touches the database. That's fixed: `render.yaml` now points
`healthCheckPath` at `/healthz`, which runs a real query and returns 503 if the
database is unreachable. If a deploy fails now, the health check is doing its
job — look at the actual error in the deploy log rather than assuming it's fine
because the process booted.

## 1. Create a free external Postgres

The Render blueprint's own free Postgres plan expires 30 days after creation —
that's the other half of what caused the 23 failed deploys (`db:migrate` in
`bin/render-build.sh` fails against an expired database, and `set -o errexit`
then fails the whole build). The `databases:` block in `render.yaml` is
commented out for this reason; it is **not deleted** — see the note in that
file for why, and resolve whether to remove it in the Render dashboard
yourself, since a blueprint sync's handling of a removed database block isn't
something to guess at from code.

1. Create a free Postgres on **Neon** or **Supabase**.
2. Copy its connection string.
3. **Verify Postgres LISTEN/NOTIFY works on it before deploying** — this is
   the single most important check in this whole document, because if it
   silently doesn't work, nothing tells you. Production Action Cable
   (`config/cable.yml`) uses the `postgresql` adapter, which depends on
   LISTEN/NOTIFY over the connection you give it. Many free/pooled Postgres
   tiers proxy connections through something like PgBouncer in
   transaction-pooling mode, which does **not** support it.
   - Quickest check: open `psql` against the connection string and run
     `LISTEN test_channel;` in one session, `NOTIFY test_channel, 'hi';` in
     another. If the first session doesn't see the notification, this
     connection string won't work for cable.
   - If your provider offers both a pooled and a **direct** (non-pooled)
     connection string, use the direct one — LISTEN/NOTIFY needs a real,
     dedicated backend connection.
   - If there's no direct option: swap `config/cable.yml`'s production
     adapter to `solid_cable` (DB-table-backed, works over a pooled
     connection since it polls instead of holding a session open — real
     work, not a toggle) or add a free Redis tier (Upstash, or Render's own)
     and use the standard Redis adapter instead.
   - **If this is silently broken:** the app will not error, anywhere. Pages
     render, forms submit, boards load. What's missing is live updates only
     — no badge counts changing, no card tiles appearing for a second viewer,
     no board sync between two open tabs. See the verification list below for
     the concrete way to catch this before you assume it works.

## 2. Set environment variables in the Render dashboard

Everything below is `sync: false` in `render.yaml` — declared so it shows up
as something to fill in, but the value itself has to be set by hand.

| Variable | Where the value comes from |
|---|---|
| `DATABASE_URL` | The connection string from step 1 (the direct one, if you have a choice — see the LISTEN/NOTIFY note above) |
| `RAILS_MASTER_KEY` | `config/master.key` in this repo (don't commit it; copy its contents) |
| `CLOUDINARY_URL` | Your Cloudinary account's dashboard → API keys |
| `MAPBOX_PUBLIC_TOKEN` | Your Mapbox account → Tokens (the **public** token — this ships to the browser by design) |
| `APP_HOST` | Your Render URL (`team-sync.onrender.com`) or a custom domain once you have one |
| `MAILER_FROM` | The From: address for outgoing mail, e.g. `no-reply@yourdomain` |
| `SMTP_ADDRESS`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Your chosen SMTP provider (none is hardcoded — pick one) |
| `SMTP_PORT` | Optional, defaults to `587` |
| `SMTP_DOMAIN` | Optional, defaults to `APP_HOST` |

Everything else in `render.yaml`'s `envVars` (`RAILS_ENV`, `WEB_CONCURRENCY`,
etc.) already has a literal value and needs nothing from you.

## 3. Deploy and watch the build log

Sync the blueprint (or push, if auto-deploy is on) and watch the build log for
`bundle exec rails db:migrate` actually succeeding — that step is what the
expired free Postgres broke before. A failure here means step 1 or 2 wasn't
completed correctly, not a code problem.

## 4. Post-deploy verification

Do these in order, on the real deployed URL, before calling it done:

1. **Sign in.** Confirms the app boots and the database is reachable (the
   health check already told you this, but confirm it end to end).
2. **Load a board.** Confirms lists/cards render and asset precompilation
   worked.
3. **Open a board's map view and confirm it renders a map, not the error
   card.** If it shows the error card, `MAPBOX_PUBLIC_TOKEN` is missing or
   wrong — this was the exact bug this deploy fixes (the token wasn't
   declared in `render.yaml` at all before).
4. **Open the same board in two browsers (or one normal + one private
   window), signed in as two different users. Make a change in one — move a
   card, add a comment — and confirm it appears in the other without a
   reload.** This is the ONLY reliable way to catch a broken LISTEN/NOTIFY
   connection. If it doesn't appear, go back to step 1's LISTEN/NOTIFY check
   — the rest of the app will look completely fine.
5. **Request a password reset and confirm the page renders without a 500.**
   This exercises the mailer config (`APP_HOST`, `MAILER_FROM`, `SMTP_*`)
   even if you don't have inbox access to see the email itself land.

## Known trade-off: due-date reminders are off

`render.yaml`'s Solid Queue worker service is commented out — it's a paid
Render plan, and paying for it wasn't approved. With it disabled,
`DueSoonScanJob` (the hourly due-date reminder scan in
`config/recurring.yml`) **does not run in production.** No due-soon
notifications will fire. Nothing else in the app depends on that worker —
this is an accepted, deliberate trade for staying on free-tier hosting, not a
bug. Re-enabling it later just means uncommenting that block in `render.yaml`
and accepting the Starter-plan cost.
