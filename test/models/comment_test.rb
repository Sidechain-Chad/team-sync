require "test_helper"

class CommentTest < ActiveSupport::TestCase
  # after_create_commit delivers Notifications, whose own after_create_commit
  # broadcasts via a Turbo Streams job — see NotificationTest for why this
  # needs the :test adapter under transactional fixtures + the app's default
  # :async adapter.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "commenting notifies every other card member but not the commenter" do
    card = cards(:one)
    commenter = users(:one)
    other_member = users(:two)
    card.members << commenter unless card.members.include?(commenter)
    card.members << other_member

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "Hello", user: commenter)
    end

    notification = Notification.last
    assert_equal other_member, notification.recipient
    assert_equal commenter, notification.actor
    assert_equal "comment", notification.action
    assert_equal 0, commenter.notifications.count
  end

  test "commenting does not notify a board member who isn't a card member" do
    card = cards(:one)
    commenter = users(:one)
    board_member_not_on_card = users(:two)
    card.list.board.board_users.create!(user: board_member_not_on_card)
    card.members << commenter unless card.members.include?(commenter)

    assert_no_difference "Notification.count" do
      card.comments.create!(content: "Hello", user: commenter)
    end
  end

  # --- @mentions (Arc 2) ---

  test "mentioning a board member creates a mention notification with the commenter as actor" do
    card = cards(:one)
    commenter = users(:one)
    bob = User.create!(email: "bob@example.com", password: "password", name: "Bob")
    card.list.board.board_users.create!(user: bob)

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "Hey @Bob take a look", user: commenter)
    end

    notification = Notification.last
    assert_equal bob, notification.recipient
    assert_equal commenter, notification.actor
    assert_equal "mention", notification.action
  end

  test "a mentioned board member who is not a card member is still notified (pull-in)" do
    card = cards(:one)
    commenter = users(:one)
    bob = User.create!(email: "bob@example.com", password: "password", name: "Bob")
    card.list.board.board_users.create!(user: bob)
    assert_not_includes card.members, bob

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "@Bob can you weigh in?", user: commenter)
    end

    assert_equal "mention", Notification.last.action
  end

  test "a card member who is also mentioned gets exactly one notification, the mention" do
    card = cards(:one)
    commenter = users(:one)
    bob = User.create!(email: "bob@example.com", password: "password", name: "Bob")
    card.list.board.board_users.create!(user: bob)
    card.members << bob

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "@Bob you're on this card already", user: commenter)
    end

    assert_equal "mention", Notification.last.action
  end

  test "un-mentioned other card members still get the plain comment notification alongside a mention" do
    card = cards(:one)
    commenter = users(:one)
    bob = User.create!(email: "bob@example.com", password: "password", name: "Bob")
    other_member = users(:two)
    card.list.board.board_users.create!(user: bob)
    card.members << bob
    card.members << other_member

    assert_difference "Notification.count", 2 do
      card.comments.create!(content: "@Bob take a look", user: commenter)
    end

    bob_notification = Notification.find_by(recipient: bob)
    other_notification = Notification.find_by(recipient: other_member)
    assert_equal "mention", bob_notification.action
    assert_equal "comment", other_notification.action
  end

  test "mentioning yourself creates no notification" do
    card = cards(:one)
    commenter = users(:one)
    card.members << commenter unless card.members.include?(commenter)

    assert_no_difference "Notification.count" do
      card.comments.create!(content: "@#{commenter.display_name} noted, doing it now", user: commenter)
    end
  end

  test "a bogus mention with no matching board member creates no notification and does not raise" do
    card = cards(:one)
    commenter = users(:one)
    card.members << commenter unless card.members.include?(commenter)

    assert_no_difference "Notification.count" do
      assert_nothing_raised do
        card.comments.create!(content: "@Nobody is around to see this", user: commenter)
      end
    end
  end

  test "boundary: @Jo does not mention John, and @John does not mention Johnny" do
    card = cards(:one)
    commenter = users(:one)
    john = User.create!(email: "john@example.com", password: "password", name: "John")
    johnny = User.create!(email: "johnny@example.com", password: "password", name: "Johnny")
    card.list.board.board_users.create!(user: john)
    card.list.board.board_users.create!(user: johnny)

    assert_no_difference "Notification.count" do
      card.comments.create!(content: "@Jo where are you?", user: commenter)
    end

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "@John can you check this?", user: commenter)
    end
    assert_equal john, Notification.last.recipient
  end

  test "an email address does not phantom-mention a member whose name matches the domain" do
    card = cards(:one)
    commenter = users(:one)
    bob = User.create!(email: "bob@example.com", password: "password", name: "Bob")
    card.list.board.board_users.create!(user: bob)

    assert_no_difference "Notification.count" do
      card.comments.create!(content: "ping john@Bob.com about this", user: commenter)
    end
  end

  # --- watching: a comment reaches the card's SUBSCRIBERS, not just its members ---
  #
  # Watching widens the audience of the existing `comment` trigger. It adds no new
  # event type and no Notification::PREFERENCE_TYPES entry — a watcher's comment
  # notification is gated by their own existing `comment` preference, which
  # Notification.deliver already enforces. The "watching turned off" test below is
  # the proof of that, in place of a toggle.

  # A watcher need not be a board member for the notification itself to be
  # delivered (delivery doesn't consult board membership), but in the real app
  # they always are, since watching goes through a board-scoped find. Keep the
  # fixtures honest about that.
  def watcher_on(card, email:)
    user = User.create!(email: email, password: "password")
    card.list.board.board_users.create!(user: user)
    CardWatcher.create!(card: card, user: user)
    user
  end

  test "a WATCHER who is not a card member is notified of a new comment" do
    card = cards(:one)
    commenter = users(:one)
    watcher = watcher_on(card, email: "comment-watcher@example.com")

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "Something worth watching", user: commenter)
    end

    notification = Notification.last
    assert_equal watcher, notification.recipient
    assert_equal commenter, notification.actor
    assert_equal "comment", notification.action
    assert_not_includes card.members, watcher, "watching must not imply membership"
  end

  test "card members are still notified once watchers are in the mix (no regression)" do
    card = cards(:one)
    commenter = users(:one)
    member = users(:two)
    card.list.board.board_users.create!(user: member)
    card.members << member
    watcher = watcher_on(card, email: "comment-both-audiences@example.com")

    assert_difference "Notification.count", 2 do
      card.comments.create!(content: "Everyone hears this", user: commenter)
    end

    assert_equal [member, watcher].sort_by(&:id),
                 Notification.last(2).map(&:recipient).sort_by(&:id)
  end

  test "the comment author gets nothing even if they are watching the card" do
    card = cards(:one)
    commenter = users(:one)
    CardWatcher.create!(card: card, user: commenter)

    assert_no_difference "Notification.count" do
      card.comments.create!(content: "Talking to myself", user: commenter)
    end
    assert_equal 0, commenter.notifications.count
  end

  test "a watcher with the comment preference OFF gets nothing (no new preference type needed)" do
    card = cards(:one)
    commenter = users(:one)
    watcher = watcher_on(card, email: "comment-pref-off@example.com")
    watcher.update!(notification_preferences: { "comment" => false })

    assert_no_difference "Notification.count" do
      card.comments.create!(content: "Muted for this watcher", user: commenter)
    end
  end

  test "a watcher who is also mentioned gets exactly one notification, the mention" do
    card = cards(:one)
    commenter = users(:one)
    watcher = watcher_on(card, email: "comment-mentioned-watcher@example.com")
    watcher.update!(name: "Wanda")

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "@Wanda take a look", user: commenter)
    end

    notification = Notification.last
    assert_equal watcher, notification.recipient
    assert_equal "mention", notification.action, "the mention must win over the plain comment"
  end

  test "someone who is BOTH a member and a watcher is notified exactly once" do
    card = cards(:one)
    commenter = users(:one)
    both = users(:two)
    card.list.board.board_users.create!(user: both)
    card.members << both
    CardWatcher.create!(card: card, user: both)

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "Only one of these, please", user: commenter)
    end

    assert_equal both, Notification.last.recipient
    assert_equal 1, both.notifications.where(action: "comment").count
  end

  # --- board watching widens this trigger's audience too ---

  def board_watcher_on(card, email:)
    user = User.create!(email: email, password: "password")
    card.list.board.board_users.create!(user: user)
    BoardWatcher.create!(board: card.list.board, user: user)
    user
  end

  test "a BOARD WATCHER who is neither a card member nor a card watcher is notified of a new comment" do
    card = cards(:one)
    commenter = users(:one)
    watcher = board_watcher_on(card, email: "comment-board-watcher@example.com")

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "Board-wide watching works", user: commenter)
    end

    notification = Notification.last
    assert_equal watcher, notification.recipient
    assert_equal commenter, notification.actor
    assert_equal "comment", notification.action
    assert_not_includes card.members, watcher
    assert_not_includes card.watchers, watcher
  end

  test "someone who is BOTH a board watcher and a card member is notified exactly once" do
    card = cards(:one)
    commenter = users(:one)
    both = users(:two)
    card.list.board.board_users.create!(user: both)
    card.members << both
    BoardWatcher.create!(board: card.list.board, user: both)

    assert_difference "Notification.count", 1 do
      card.comments.create!(content: "Only one of these, please, board edition", user: commenter)
    end

    assert_equal both, Notification.last.recipient
    assert_equal 1, both.notifications.where(action: "comment").count
  end

  test "a board watcher with the comment preference OFF gets nothing" do
    card = cards(:one)
    commenter = users(:one)
    watcher = board_watcher_on(card, email: "comment-board-watcher-pref-off@example.com")
    watcher.update!(notification_preferences: { "comment" => false })

    assert_no_difference "Notification.count" do
      card.comments.create!(content: "Muted for this board watcher", user: commenter)
    end
  end
end
