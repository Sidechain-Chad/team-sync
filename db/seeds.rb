# TeamSync development seeds.
#
# Goal: a fresh `bin/rails db:reset` produces a database where EVERY built
# feature is visible without clicking anything into existence first. If you add
# a feature, add something here that demonstrates it.
#
# Rules this file follows (please keep to them):
#
#   * Deterministic. No randomness, no Faker — screenshots and manual checks
#     must be stable between runs.
#   * Relative dates only. `3.days.from_now`, never a literal date, or the
#     seeds go stale and the Planner/due pills stop demonstrating anything.
#     Some cards deliberately land inside the Planner's 22-day window
#     (today..today+21) and inside the due-soon window (< 24h).
#   * Every user's password is `password`.
#   * Assumes an empty database (`db:reset`). The cleanup below only exists so
#     a bare `db:seed` on a dirty database is also repeatable.
#
# BOARD after_create CALLBACKS: Board seeds ten default labels and three default
# lists ("To Do"/"Doing"/"Done") on create. Both are deliberate app behaviour, so
# this file works WITH them:
#   * Labels — the default ten (colour, no name) are kept on every board; three
#     boards rename a few of them, so both named and unnamed labels are
#     exercised in the picker.
#   * Lists — kept as-is on the boards where "To Do/Doing/Done" is genuinely what
#     we want (Design System, Q2 Retrospective, Personal Errands); explicitly
#     destroyed and replaced on the boards that need a specific pipeline
#     (Product Launch, Marketing Site). Same `lists.destroy_all` dance
#     Board#copy_to does for the same reason.

# ---------------------------------------------------------------------------
# Attachment guard
# ---------------------------------------------------------------------------
# Development stores attachments on Cloudinary, and each upload costs 1-4s of
# network. Two reasons this is guarded rather than unconditional:
#
#   1. A developer who has just cloned the repo has no CLOUDINARY_URL. Without
#      this guard `db:reset` would raise partway through and they'd have no
#      usable database at all — the seeds must degrade, not fail.
#   2. Uploads dominate the runtime, so keeping the count low (4 images + 1 PDF)
#      is what keeps seeding to a few seconds.
#
# Set SEED_SKIP_ATTACHMENTS=1 to skip them deliberately (faster reseeds).
ATTACHMENTS_ENABLED = begin
  if ENV["SEED_SKIP_ATTACHMENTS"].present?
    false
  elsif !ActiveStorage::Blob.service.class.name.to_s.include?("Cloudinary")
    true # Disk service — nothing to configure
  else
    c = Cloudinary.config
    c.cloud_name.present? && c.api_key.present? && c.api_secret.present?
  end
rescue StandardError
  false
end

ASSETS = Rails.root.join("db/seed_assets")

# Attach an asset, or skip loudly. Any failure (bad credentials, network down,
# Cloudinary rejecting the file) degrades to a console notice — a seeded
# database with no images is far more useful than a half-seeded one.
def attach_asset(record, association, filename, content_type, description)
  unless ATTACHMENTS_ENABLED
    puts "    - skipped #{description} (attachments disabled)"
    return
  end

  ASSETS.join(filename).open do |io|
    record.public_send(association).attach(io: io, filename: filename, content_type: content_type)
  end
  puts "    + attached #{description}"
rescue StandardError => e
  puts "    ! skipped #{description} — #{e.class}: #{e.message.to_s.truncate(120)}"
end

# ---------------------------------------------------------------------------
# Clean slate
# ---------------------------------------------------------------------------
puts "Cleaning database..."
# Boards cascade to lists -> cards -> checklists/comments/activities/labels, and
# users cascade to the boards they own. Notifications are polymorphic and so
# un-FK-able; they go first and explicitly.
Notification.delete_all
Activity.delete_all
Board.destroy_all
User.destroy_all

# ---------------------------------------------------------------------------
# Users — all password "password"
# ---------------------------------------------------------------------------
# Distinct names so avatar initials AND the generated avatar colours differ.
# Two carry uploaded avatars, three fall back to initials, so both render paths
# are visible side by side on the same board.
puts "Creating users..."

demo      = User.create!(email: "demo@example.com",      name: "Demo User",         password: "password", password_confirmation: "password")
ada       = User.create!(email: "ada@example.com",       name: "Ada Lovelace",      password: "password", password_confirmation: "password")
grace     = User.create!(email: "grace@example.com",     name: "Grace Hopper",      password: "password", password_confirmation: "password")
alan      = User.create!(email: "alan@example.com",      name: "Alan Turing",       password: "password", password_confirmation: "password")
katherine = User.create!(email: "katherine@example.com", name: "Katherine Johnson", password: "password", password_confirmation: "password")

attach_asset(ada,   :avatar, "avatar_ada.png",   "image/png", "Ada Lovelace avatar")
attach_asset(grace, :avatar, "avatar_grace.png", "image/png", "Grace Hopper avatar")

# ---------------------------------------------------------------------------
# Relative dates — every date in this file derives from these.
# ---------------------------------------------------------------------------
# TODAY_LATE is both "due today" and "due soon": end_of_day is always the
# current calendar day and always less than 24h away, whatever time of day the
# seeds are run at. A literal "today at 14:00" would silently become an OVERDUE
# card whenever someone seeded after 2pm.
OVERDUE_AT  = 2.days.ago.change(hour: 17)
TODAY_LATE  = Date.current.end_of_day          # due today AND inside the 24h due-soon window
SOON_HOURS  = 3.hours.from_now                 # also inside the due-soon window
FEW_DAYS    = 5.days.from_now.change(hour: 12) # inside the Planner's 22-day window
NEXT_WEEK   = 9.days.from_now.change(hour: 12)
RANGE_START = 2.days.ago.change(hour: 9)       # spans today, so the agenda shows it live
RANGE_END   = 9.days.from_now.change(hour: 17)

# ===========================================================================
# BOARD 1 — "Product Launch"
# The showcase board: photo background, favourited, five members, custom
# pipeline, and the home of most feature demonstrations.
# ===========================================================================
puts "Creating board: Product Launch..."
launch = Board.create!(name: "Product Launch", user: demo)
[ada, grace, alan, katherine].each { |u| launch.board_users.create!(user: u) }
BoardFavorite.create!(board: launch, user: demo)
attach_asset(launch, :background, "board_background.jpg", "image/jpeg", "Product Launch background photo")

# Keep the ten default colour labels; name five of them. The unnamed five stay
# so the picker shows both states.
launch_labels = launch.labels.index_by(&:color)
{ "green" => "Ready", "red" => "Blocked", "blue" => "Design",
  "yellow" => "Needs QA", "purple" => "Research" }.each do |color, name|
  launch_labels[color].update!(name: name)
end
label = ->(color) { launch_labels[color] }

# Custom pipeline — the default To Do/Doing/Done isn't the structure we want.
launch.lists.destroy_all
backlog  = launch.lists.create!(name: "Backlog",     position: 1)
design   = launch.lists.create!(name: "Design",      position: 2)
progress = launch.lists.create!(name: "In Progress", position: 3, card_limit: 3) # deliberately OVER limit below
review   = launch.lists.create!(name: "Review",      position: 4)
shipped  = launch.lists.create!(name: "Shipped",     position: 5)
launch.lists.create!(name: "Icebox", position: 6) # deliberately EMPTY — exercises the empty-list state

# --- Backlog -------------------------------------------------------------
c_pricing = Card.create!(
  list: backlog, title: "Draft pricing page copy",
  description: "Three tiers, annual toggle. Legal to review the fine print before we ship."
)
c_pricing.labels << label.("purple")
c_pricing.members << katherine

c_competitor = Card.create!(
  list: backlog, title: "Competitor teardown",
  description: "Compare onboarding flows for the three closest products."
)
c_competitor.labels << label.("purple") << label.("sky")

# Watched by demo, who is NOT a member — the watch badge shows for demo only.
c_infra = Card.create!(
  list: backlog, title: "Decide on CDN provider",
  description: "Latency numbers from the last spike are in the shared doc."
)
c_infra.members << alan
CardWatcher.create!(card: c_infra, user: demo)

# --- Design --------------------------------------------------------------
# Range card: start + due spanning several days -> Planner bar + agenda entry.
c_brandkit = Card.create!(
  list: design, title: "Brand kit refresh",
  description: "Logo lockups, colour tokens and the illustration set, all in one pass.",
  start_date: RANGE_START, due_date: RANGE_END
)
c_brandkit.labels << label.("blue")
c_brandkit.members << ada << grace

# Image cover — card_cover_url picks the first image attachment.
c_hero = Card.create!(
  list: design, title: "Hero illustration",
  description: "Final artwork for the top of the marketing page."
)
c_hero.labels << label.("blue")
c_hero.members << ada
attach_asset(c_hero, :attachments, "card_cover.jpg", "image/jpeg", "Hero illustration cover image")

# --- In Progress (WIP limit 3, four ACTIVE cards -> OVER) -----------------
c_checkout = Card.create!(
  list: progress, title: "Checkout flow rebuild",
  description: "Split the single-page checkout into three steps with a progress indicator.",
  due_date: OVERDUE_AT                                   # OVERDUE
)
c_checkout.labels << label.("red") << label.("yellow")
c_checkout.members << demo << ada

c_emails = Card.create!(
  list: progress, title: "Transactional email templates",
  description: "Receipt, password reset and invite emails need the new header.",
  due_date: TODAY_LATE                                   # DUE TODAY + due-soon
)
c_emails.labels << label.("yellow")
c_emails.members << demo << grace

c_onboard = Card.create!(
  list: progress, title: "Onboarding checklist widget",
  description: "Four-step checklist on first login, dismissible.",
  due_date: SOON_HOURS                                   # due-soon
)
c_onboard.labels << label.("green")
c_onboard.members << alan

c_search = Card.create!(
  list: progress, title: "Search relevance tuning",
  description: "Trigram thresholds are too permissive on short queries.",
  due_date: FEW_DAYS                                     # a few days out
)
c_search.labels << label.("sky")
c_search.members << demo

# --- Review --------------------------------------------------------------
# Non-image attachment — card_cover_url skips non-images, so this card shows an
# attachment count but NO cover image.
c_brief = Card.create!(
  list: review, title: "Launch brief sign-off",
  description: "Final brief for the exec review. PDF attached.",
  due_date: NEXT_WEEK
)
c_brief.members << demo << katherine
attach_asset(c_brief, :attachments, "launch_brief.pdf", "application/pdf", "Launch brief PDF (non-image attachment)")

# Location card -> shows on the Map view.
c_venue = Card.create!(
  list: review, title: "Book the launch venue",
  description: "Capacity 120, AV included. Hold expires at the end of the month.",
  due_date: FEW_DAYS,
  latitude: 51.505_300, longitude: -0.075_400,
  location_name: "Tower Bridge Studios",
  location_address: "Shad Thames, London SE1 2YE, United Kingdom"
)
c_venue.labels << label.("green")
c_venue.members << grace

# A SECOND location card on this board, deliberately: with one located card the
# map takes board_map_controller's single-point `setCenter` branch, with two it
# takes `fitBounds`. Seeding two here means the showcase board exercises the
# path that actually reads like a map, and Marketing Site's single pin still
# covers the other branch.
c_backup_venue = Card.create!(
  list: review, title: "View the backup venue",
  description: "Second option if the Shad Thames hold falls through.",
  due_date: NEXT_WEEK,
  latitude: 51.513_800, longitude: -0.098_600,
  location_name: "Guildhall Yard",
  location_address: "Gresham St, London EC2V 7HH, United Kingdom"
)
c_backup_venue.members << katherine

# --- Shipped -------------------------------------------------------------
# Completed card — due_status becomes :complete and the tile shows the filled
# green check plus the board-tile archive affordance.
c_analytics = Card.create!(
  list: shipped, title: "Analytics event schema",
  description: "Shipped behind a flag; dashboards updated.",
  due_date: 4.days.ago, completed: true
)
c_analytics.labels << label.("green")
c_analytics.members << demo

# Archived card — keeps "Archived items" from being empty. Archived cards are
# excluded from active_cards, so this does NOT count towards a WIP limit.
c_oldnav = Card.create!(
  list: shipped, title: "Old navigation prototype",
  description: "Superseded by the sidebar redesign. Kept for reference.",
  archived_at: 3.days.ago
)
c_oldnav.labels << label.("black")

# --- Checklists ----------------------------------------------------------
# One PARTIALLY complete (tile shows 2/4), one FULLY complete (tile shows the
# success-tinted 3/3 pill).
cl_partial = Checklist.create!(card: c_checkout, title: "Steps", position: 1)
[["Cart summary step", true], ["Address step", true],
 ["Payment step", false], ["Confirmation step", false]].each_with_index do |(content, done), i|
  ChecklistItem.create!(checklist: cl_partial, content: content, completed: done, position: i + 1)
end

cl_full = Checklist.create!(card: c_analytics, title: "Rollout", position: 1)
[["Schema reviewed", true], ["Flag enabled in staging", true],
 ["Dashboards updated", true]].each_with_index do |(content, done), i|
  ChecklistItem.create!(checklist: cl_full, content: content, completed: done, position: i + 1)
end

cl_brandkit = Checklist.create!(card: c_brandkit, title: "Deliverables", position: 1)
[["Logo lockups", true], ["Colour tokens", false],
 ["Illustration set", false]].each_with_index do |(content, done), i|
  ChecklistItem.create!(checklist: cl_brandkit, content: content, completed: done, position: i + 1)
end

# --- Comments (including @mentions) --------------------------------------
# Comment has an after_create_commit that fans notifications out to mentioned
# users and to the card's subscribers. Seeded comments therefore generate real
# notification rows as a side effect — which is exactly what we want for the
# bell. Mentions must match User#display_name exactly (Comment#body_mentions?).
Comment.create!(card: c_checkout, user: ada,
                content: "Pushed the address-step branch. @Demo User can you look at the validation copy?")
Comment.create!(card: c_checkout, user: demo,
                content: "Looked — copy is fine, but the postcode field needs a wider input on mobile.")
Comment.create!(card: c_brandkit, user: grace,
                content: "Colour tokens are blocked on the contrast audit. @Ada Lovelace has the spreadsheet.")
Comment.create!(card: c_venue, user: katherine,
                content: "Venue confirmed the hold. Deposit is due before the end of the month.")
Comment.create!(card: c_hero, user: ada,
                content: "First pass attached. Happy to redraw the figure if it reads too busy.")
# Demo is a member of this card and is NOT mentioned, so this one produces a
# plain `comment` notification rather than a `mention` — without it demo's feed
# would have no example of that type.
Comment.create!(card: c_search, user: grace,
                content: "Bumped the trigram threshold to 0.3 locally and short queries behave much better.")

# ===========================================================================
# BOARD 2 — "Design System"
# Gradient cover (no background attached), favourited, and DELIBERATELY keeps
# the three default lists so the after_create default path stays visible.
# ===========================================================================
puts "Creating board: Design System..."
design_system = Board.create!(name: "Design System", user: demo)
design_system.board_users.create!(user: grace)
BoardFavorite.create!(board: design_system, user: demo)

ds_todo, ds_doing, ds_done = design_system.lists.order(:position).to_a # "To Do" / "Doing" / "Done"
ds_labels = design_system.labels.index_by(&:color)
ds_labels["orange"].update!(name: "Component")
ds_labels["lime"].update!(name: "Docs")

ds_tokens = Card.create!(list: ds_todo, title: "Audit spacing tokens",
                         description: "Three scales are in use. Collapse to one.")
ds_tokens.labels << ds_labels["orange"]

ds_icons = Card.create!(list: ds_todo, title: "Document the icon set",
                        description: "Usage rules, sizing, and when to use solid vs regular.")
ds_icons.labels << ds_labels["lime"]

ds_modal = Card.create!(list: ds_doing, title: "Modal component",
                        description: "Focus trap, Esc-to-close, and a documented z-index tier.",
                        due_date: FEW_DAYS)
ds_modal.labels << ds_labels["orange"]
ds_modal.members << grace << demo

Card.create!(list: ds_done, title: "Button variants",
             description: "Primary, secondary and destructive, all contrast-checked.",
             due_date: 8.days.ago, completed: true)

# ===========================================================================
# BOARD 3 — "Marketing Site"
# Owned by GRACE and shared with demo, so the boards index "Shared with me"
# section populates and owned-vs-shared is visibly different.
# ===========================================================================
puts "Creating board: Marketing Site (owned by Grace, shared with demo)..."
marketing = Board.create!(name: "Marketing Site", user: grace)
[demo, ada].each { |u| marketing.board_users.create!(user: u) }

marketing.lists.destroy_all
mk_ideas   = marketing.lists.create!(name: "Ideas",     position: 1)
mk_writing = marketing.lists.create!(name: "Writing",   position: 2)
mk_live    = marketing.lists.create!(name: "Published", position: 3)

mk_labels = marketing.labels.index_by(&:color)
mk_labels["pink"].update!(name: "Campaign")

Card.create!(list: mk_ideas, title: "Customer story: Northwind",
             description: "They cut onboarding time in half. Worth a long-form piece.")

mk_case = Card.create!(list: mk_writing, title: "Case study: migration in a weekend",
                       description: "Draft is with the customer for approval.",
                       start_date: 1.day.from_now.change(hour: 9),
                       due_date: 6.days.from_now.change(hour: 17))
mk_case.labels << mk_labels["pink"]
mk_case.members << demo << ada

mk_launch = Card.create!(list: mk_writing, title: "Launch-day blog post",
                         description: "Embargoed until the announcement goes out.",
                         due_date: NEXT_WEEK)
mk_launch.members << grace

# A second location card so the Map has more than one pin.
mk_photo = Card.create!(list: mk_ideas, title: "Photo shoot — office",
                        description: "Team shots for the about page.",
                        latitude: 51.523_800, longitude: -0.086_100,
                        location_name: "Old Street Studio",
                        location_address: "Old St, London EC1V 9NR, United Kingdom")
mk_photo.members << ada

Card.create!(list: mk_live, title: "Pricing page refresh",
             description: "Live since last week; conversion is up slightly.",
             due_date: 6.days.ago, completed: true)

Comment.create!(card: mk_case, user: grace,
                content: "Customer approved with one tweak to the headline. @Demo User over to you for the CMS entry.")

# ===========================================================================
# BOARD 4 — "Q2 Retrospective" (CLOSED)
# Absent from the boards index, present on /boards/closed, still reachable by
# direct URL with the closed banner.
# ===========================================================================
puts "Creating board: Q2 Retrospective (closed)..."
retro = Board.create!(name: "Q2 Retrospective", user: demo)
retro_todo, retro_doing, retro_done = retro.lists.order(:position).to_a # keeps the defaults
Card.create!(list: retro_todo,  title: "What should we stop doing?",
             description: "Collected from the team survey.")
Card.create!(list: retro_doing, title: "Action: shorten the release checklist",
             description: "Owner: Alan. Target is the next cycle.")
Card.create!(list: retro_done,  title: "Action: weekly demo slot",
             description: "Running since week 3.", completed: true)
retro.close!

# ===========================================================================
# BOARD 5 — "Personal Errands"
# Owned by demo, gradient, NOT favourited and NOT shared — so the index shows a
# plain un-starred single-member tile alongside the decorated ones.
# ===========================================================================
puts "Creating board: Personal Errands..."
errands = Board.create!(name: "Personal Errands", user: demo)
er_todo, er_doing, _er_done = errands.lists.order(:position).to_a # keeps the defaults
Card.create!(list: er_todo,  title: "Renew domain registration", due_date: NEXT_WEEK)
Card.create!(list: er_todo,  title: "Book dentist")
Card.create!(list: er_doing, title: "Replace laptop battery",
             description: "Out of warranty; the third-party quote is cheaper.")

# ===========================================================================
# Activities
# ===========================================================================
# Nothing in the app back-fills these, so board Activity and the card feeds
# render empty on a fresh seed unless we write them explicitly. Actions must be
# ones Activity#message knows about or they fall through to its generic
# fallback. created_at is set explicitly so the feed has a believable order.
puts "Creating activities..."
[
  [c_checkout,  demo,      "created",                  nil,                             6.days.ago],
  [c_checkout,  ada,       "moved",                    "Design to In Progress",         5.days.ago],
  [c_checkout,  ada,       "added_checklist",          "Steps",                         5.days.ago],
  [c_checkout,  ada,       "completed_checklist_item", "Cart summary step",             4.days.ago],
  [c_checkout,  ada,       "completed_checklist_item", "Address step",                  3.days.ago],
  [c_checkout,  demo,      "set_due_date",             OVERDUE_AT.strftime("%d %b %Y"), 3.days.ago],
  [c_checkout,  demo,      "edited_description",       nil,                             2.days.ago],
  [c_brandkit,  grace,     "created",                  nil,                             7.days.ago],
  [c_brandkit,  grace,     "renamed",                  "Brand kit refresh",             6.days.ago],
  [c_brandkit,  ada,       "added_checklist",          "Deliverables",                  4.days.ago],
  [c_brandkit,  ada,       "completed_checklist_item", "Logo lockups",                  2.days.ago],
  [c_hero,      ada,       "created",                  nil,                             5.days.ago],
  [c_hero,      ada,       "added_attachment",         "card_cover.jpg",                2.days.ago],
  [c_venue,     katherine, "created",                  nil,                             4.days.ago],
  [c_venue,     katherine, "set_due_date",             FEW_DAYS.strftime("%d %b %Y"),   3.days.ago],
  [c_analytics, demo,      "created",                  nil,                             9.days.ago],
  [c_analytics, demo,      "moved",                    "In Progress to Shipped",        5.days.ago],
  [c_analytics, demo,      "completed_card",           nil,                             4.days.ago],
  [c_oldnav,    demo,      "created",                  nil,                             12.days.ago],
  [c_oldnav,    demo,      "archived",                 nil,                             3.days.ago],
  [c_infra,     alan,      "created",                  nil,                             6.days.ago],
  [c_search,    demo,      "created",                  nil,                             3.days.ago],
  [ds_modal,    grace,     "created",                  nil,                             5.days.ago],
  [ds_modal,    grace,     "edited_description",       nil,                             2.days.ago],
  [mk_case,     grace,     "created",                  nil,                             6.days.ago],
  [mk_case,     ada,       "moved",                    "Ideas to Writing",              4.days.ago],
  [mk_launch,   grace,     "created",                  nil,                             3.days.ago]
].each do |card, user, action, description, at|
  Activity.create!(card: card, user: user, action: action, description: description,
                   created_at: at, updated_at: at)
end

# ===========================================================================
# Notifications for demo
# ===========================================================================
# The Comment callbacks above already produced real `comment`/`mention` rows for
# demo. This block tops them up so the bell shows several UNREAD across several
# types, plus a couple already read.
#
# Written with create! rather than Notification.deliver: deliver is the runtime
# seam (it consults the recipient's preferences and no-ops on self-notification)
# and would silently produce nothing if a preference were ever off — that makes
# a seed file quietly wrong instead of loudly wrong.
puts "Creating notifications..."

# Everything the comment callbacks generated starts unread. Mark only the OLDEST
# read: that leaves demo with an unread `mention` and an unread `comment` (the
# two types only the callbacks can produce) while still showing a read row.
Notification.where(recipient: demo).order(:created_at).first&.update!(read_at: 1.day.ago)

[
  { actor: ada,       notifiable: c_checkout,  action: "added_to_card",     read_at: nil,        created_at: 5.hours.ago },
  { actor: grace,     notifiable: c_brandkit,  action: "added_to_card",     read_at: nil,        created_at: 8.hours.ago },
  { actor: nil,       notifiable: c_emails,    action: "due_soon",          read_at: nil,        created_at: 2.hours.ago },
  { actor: alan,      notifiable: c_infra,     action: "moved",             read_at: nil,        created_at: 1.hour.ago },
  { actor: grace,     notifiable: c_oldnav,    action: "archived",          read_at: nil,        created_at: 3.days.ago },
  { actor: katherine, notifiable: c_analytics, action: "removed_from_card", read_at: 2.days.ago, created_at: 4.days.ago }
].each do |attrs|
  Notification.create!(recipient: demo, **attrs)
end

# ---------------------------------------------------------------------------
puts
puts "=" * 72
puts "Seeded. Sign in as demo@example.com / password"
puts "  Every seeded user shares that password: ada@, grace@, alan@, katherine@"
puts "=" * 72
puts "  Users          #{User.count}"
puts "  Boards         #{Board.count} (#{Board.closed.count} closed)"
puts "  Lists          #{List.count}"
puts "  Cards          #{Card.count} (#{Card.archived.count} archived, #{Card.where(completed: true).count} complete)"
puts "  Labels         #{Label.count} (#{Label.where.not(name: [nil, '']).count} named)"
puts "  Checklists     #{Checklist.count} / #{ChecklistItem.count} items"
puts "  Comments       #{Comment.count}"
puts "  Activities     #{Activity.count}"
puts "  Notifications  #{Notification.count} total, #{Notification.where(recipient: User.find_by(email: 'demo@example.com')).unread.count} unread for demo"
puts "  Attachments    #{ActiveStorage::Attachment.count}#{ATTACHMENTS_ENABLED ? '' : '  [SKIPPED — no Cloudinary credentials]'}"
puts "=" * 72
