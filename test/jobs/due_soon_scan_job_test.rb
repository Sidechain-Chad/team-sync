require "test_helper"

class DueSoonScanJobTest < ActiveSupport::TestCase
  # after_create_commit on Notification broadcasts via a Turbo job — the
  # :async adapter can't see the not-really-committed row under transactional
  # fixtures, so switch to :test for the cases that actually create one.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "creates one due_soon notification per member of an eligible card and stamps due_reminder_sent_at" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    member = users(:one) # already a card member via card_members fixture :one

    assert_difference "Notification.count", 1 do
      DueSoonScanJob.perform_now
    end

    notification = Notification.last
    assert_equal member, notification.recipient
    assert_nil notification.actor
    assert_equal "due_soon", notification.action
    assert_equal card, notification.notifiable

    assert_not_nil card.reload.due_reminder_sent_at
  end

  test "a second run does not re-notify (idempotency)" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)

    DueSoonScanJob.perform_now
    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end

  # Reminders key off due_date ONLY — a start date must not change who gets
  # reminded or when, no matter where it sits relative to the window.
  test "a start date does not change due-soon eligibility" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now, start_date: 5.days.ago)

    assert_difference "Notification.count", 1 do
      DueSoonScanJob.perform_now
    end
    assert_not_nil card.reload.due_reminder_sent_at
  end

  test "a start date inside the reminder window does not make an out-of-window card eligible" do
    card = cards(:one)
    # Due well beyond the 24h window, but starting right now.
    card.update!(due_date: 10.days.from_now, start_date: Time.current)

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
    assert_nil card.reload.due_reminder_sent_at
  end

  test "a start-date-only card is never due-soon eligible" do
    card = cards(:one)
    card.update!(due_date: nil, start_date: 1.hour.from_now)

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end

  test "does not notify a member who has turned due_soon off" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    member = users(:one)
    member.update!(notification_preferences: { "due_soon" => false })

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end

  # --- watching widens this trigger's audience too ---

  test "notifies a WATCHER who is not a card member" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    card.card_members.destroy_all # drop the fixture member so the watcher is the only recipient
    watcher = User.create!(email: "due-watcher@example.com", password: "password")
    CardWatcher.create!(card: card, user: watcher)

    assert_difference "Notification.count", 1 do
      DueSoonScanJob.perform_now
    end

    notification = Notification.last
    assert_equal watcher, notification.recipient
    assert_equal "due_soon", notification.action
    assert_equal card, notification.notifiable
    assert_not_includes card.reload.members, watcher
  end

  test "notifies members AND watchers, and only once for someone who is both" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    member = users(:one) # card member via the fixture
    watcher = User.create!(email: "due-watcher-2@example.com", password: "password")
    CardWatcher.create!(card: card, user: watcher)
    # The fixture member also watches — must still be one notification for them.
    CardWatcher.create!(card: card, user: member)

    assert_difference "Notification.count", 2 do
      DueSoonScanJob.perform_now
    end

    assert_equal 1, member.notifications.where(action: "due_soon").count
    assert_equal 1, watcher.notifications.where(action: "due_soon").count
  end

  test "does not notify a watcher who has turned due_soon off" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    card.card_members.destroy_all
    watcher = User.create!(email: "due-watcher-off@example.com", password: "password",
                           notification_preferences: { "due_soon" => false })
    CardWatcher.create!(card: card, user: watcher)

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end

  # --- board watching widens this trigger's audience too ---

  test "notifies a BOARD WATCHER who is neither a card member nor a card watcher" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    card.card_members.destroy_all
    board_watcher = User.create!(email: "due-board-watcher@example.com", password: "password")
    BoardWatcher.create!(board: card.list.board, user: board_watcher)

    assert_difference "Notification.count", 1 do
      DueSoonScanJob.perform_now
    end

    notification = Notification.last
    assert_equal board_watcher, notification.recipient
    assert_equal "due_soon", notification.action
    assert_equal card, notification.notifiable
    assert_not_includes card.reload.members, board_watcher
    assert_not_includes card.reload.watchers, board_watcher
  end

  test "notifies members, card watchers, and board watchers, only once for someone who is more than one" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    member = users(:one) # card member via the fixture
    card_watcher = User.create!(email: "due-card-watcher-3@example.com", password: "password")
    board_watcher = User.create!(email: "due-board-watcher-2@example.com", password: "password")
    CardWatcher.create!(card: card, user: card_watcher)
    BoardWatcher.create!(board: card.list.board, user: board_watcher)
    # The fixture member also board-watches — must still be one notification for them.
    BoardWatcher.create!(board: card.list.board, user: member)

    assert_difference "Notification.count", 3 do
      DueSoonScanJob.perform_now
    end

    assert_equal 1, member.notifications.where(action: "due_soon").count
    assert_equal 1, card_watcher.notifications.where(action: "due_soon").count
    assert_equal 1, board_watcher.notifications.where(action: "due_soon").count
  end

  test "does not notify a board watcher who has turned due_soon off" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    card.card_members.destroy_all
    board_watcher = User.create!(email: "due-board-watcher-off@example.com", password: "password",
                                 notification_preferences: { "due_soon" => false })
    BoardWatcher.create!(board: card.list.board, user: board_watcher)

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end

  # --- N+1 guard ---
  #
  # The scan reads Card#subscribers, which touches :members, :watchers, AND (via
  # card -> list -> board) the board's :watchers. Before this arc it preloaded
  # only :members and :watchers; leaving it that way issues one
  # `boards INNER JOIN board_watchers` (plus the `lists`/`boards` lookups that
  # get there) per due card.
  #
  # This counts LOOKUP queries only (the SELECTs that resolve cards and their
  # three audiences), not every query, and that distinction is the whole design
  # of this test: the scan's TOTAL query count cannot be flat, because it
  # legitimately writes one notification row per recipient, refreshes that
  # recipient's unread badge count, and stamps due_reminder_sent_at per card.
  # Measured, that's real per-recipient work no preload can remove, and
  # asserting on the total would just be pinning delivery internals.
  #
  # What MUST stay flat is the lookup side, and it does: 1 cards SELECT + 1
  # card_members + 1 card_watchers + 2 users (members' and card watchers')
  # + 1 lists + 1 boards + 1 board_watchers + 1 users (board watchers') = 9,
  # whatever the row count. Detection proven below by dropping
  # `list: { board: :watchers }` and showing growth reappears.
  LOOKUP_TABLES = %w[cards card_members card_watchers lists boards board_watchers users].freeze

  test "lookup query count stays flat as the number of due cards with watchers grows" do
    small = count_lookups_for_scan(due_cards: 3)
    large = count_lookups_for_scan(due_cards: 6)

    assert_equal small, large,
                 "audience lookups must not grow with the number of due cards " \
                 "(got #{small} at 3 cards, #{large} at 6)"
    assert_equal 9, small, "expected exactly the nine preload SELECTs"
  end

  private

  # SELECT count against the tables the scan reads to build its audience. Writes,
  # badge COUNTs and the due_reminder stamp are excluded on purpose — see above.
  def count_lookups_for_scan(due_cards:)
    Card.update_all(due_date: nil, due_reminder_sent_at: nil)
    list = boards(:one).lists.first

    due_cards.times do |i|
      card = list.cards.create!(title: "Due #{due_cards}-#{i}", due_date: 12.hours.from_now)
      # A member, a card watcher, AND a board watcher on every card, so a
      # missing preload on any of the three shows up as growth. The board
      # watchers all watch the SAME board (there's only one here) — that's
      # fine: `list: { board: :watchers }` dedupes by board id regardless of
      # how many due cards share it, so only per-CARD growth (a query fired
      # per Card instance, since AR has no identity map across them) would
      # show up here, which is exactly the regression this guards against.
      card.members << User.create!(email: "scan-m-#{due_cards}-#{i}@example.com", password: "password")
      CardWatcher.create!(card: card, user: User.create!(email: "scan-w-#{due_cards}-#{i}@example.com", password: "password"))
      BoardWatcher.create!(board: list.board, user: User.create!(email: "scan-bw-#{due_cards}-#{i}@example.com", password: "password"))
    end

    count = 0
    counter = ->(*, payload) {
      next if payload[:name].in?(["SCHEMA", "TRANSACTION"])
      sql = payload[:sql]
      next unless sql.start_with?("SELECT")
      next if sql.include?("COUNT(*)") # the per-recipient unread badge count
      count += 1 if LOOKUP_TABLES.any? { |t| sql.include?(%("#{t}")) }
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { DueSoonScanJob.perform_now }
    count
  end
end
