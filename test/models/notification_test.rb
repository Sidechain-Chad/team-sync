require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  # after_create_commit broadcasts via a Turbo Streams job — under this
  # app's default :async adapter with transactional fixtures, that job can
  # run in a background thread that can't see the not-really-committed row.
  # The :test adapter just queues it instead. See BoardsControllerTest for
  # the same gotcha.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "unread scope returns only notifications with a nil read_at" do
    card = cards(:one)
    unread = Notification.create!(recipient: users(:one), actor: users(:two), notifiable: card, action: "added_to_card")
    read = Notification.create!(recipient: users(:one), actor: users(:two), notifiable: card, action: "added_to_card", read_at: Time.current)

    assert_includes Notification.unread, unread
    assert_not_includes Notification.unread, read
  end

  test "deliver does not create a notification when recipient == actor" do
    user = users(:one)
    card = cards(:one)

    assert_no_difference "Notification.count" do
      result = Notification.deliver(recipient: user, actor: user, notifiable: card, action: "added_to_card")
      assert_nil result
    end
  end

  test "deliver does not create a notification when recipient is nil" do
    card = cards(:one)

    assert_no_difference "Notification.count" do
      result = Notification.deliver(recipient: nil, actor: users(:two), notifiable: card, action: "added_to_card")
      assert_nil result
    end
  end

  test "deliver creates a notification when recipient and actor differ" do
    card = cards(:one)

    assert_difference "Notification.count", 1 do
      Notification.deliver(recipient: users(:one), actor: users(:two), notifiable: card, action: "added_to_card")
    end
  end

  test "deliver does not create a notification when the recipient has that type turned off" do
    recipient = users(:one)
    recipient.update!(notification_preferences: { "comment" => false })
    card = cards(:one)

    assert_no_difference "Notification.count" do
      result = Notification.deliver(recipient: recipient, actor: users(:two), notifiable: card, action: "comment")
      assert_nil result
    end
  end

  test "deliver still creates a notification for a different type the recipient left on (per-type independence)" do
    recipient = users(:one)
    recipient.update!(notification_preferences: { "comment" => false })
    card = cards(:one)

    assert_difference "Notification.count", 1 do
      Notification.deliver(recipient: recipient, actor: users(:two), notifiable: card, action: "mention")
    end
  end

  test "deliver accepts a nil actor (due_soon has no actor)" do
    card = cards(:one)

    assert_difference "Notification.count", 1 do
      notification = Notification.deliver(recipient: users(:one), actor: nil, notifiable: card, action: "due_soon")
      assert_nil notification.actor
    end
  end

  test "message renders is due soon for due_soon" do
    notification = Notification.create!(recipient: users(:one), actor: nil, notifiable: cards(:one), action: "due_soon")
    assert_equal "is due soon", notification.message
  end

  # --- notifiable cascade ---
  #
  # notifiable is polymorphic, so unlike recipient_id/actor_id it can't have a
  # real foreign key — nothing at the DB level stops a destroyed Card or Comment
  # from leaving its notifications behind. The cascade has to be declared on the
  # model side or orphans accumulate.

  test "destroying a card destroys its added_to_card notifications" do
    card = cards(:one)
    Notification.create!(recipient: users(:one), actor: users(:two), notifiable: card, action: "added_to_card")

    assert_difference "Notification.count", -1 do
      card.destroy
    end
  end

  test "destroying a card destroys its actor-less due_soon notifications" do
    card = cards(:one)
    Notification.create!(recipient: users(:one), actor: nil, notifiable: card, action: "due_soon")

    assert_difference "Notification.count", -1 do
      card.destroy
    end
  end

  # These assert on the specific rows rather than a count difference: creating a
  # comment ALSO auto-delivers a "comment" notification to each card member (see
  # Comment's after_create_commit), so a count-based assertion here would be
  # measuring that side effect as much as the cascade.

  test "destroying a comment destroys its comment notifications" do
    card = cards(:one)
    comment = card.comments.create!(user: users(:two), content: "Plain comment")
    explicit = Notification.create!(recipient: users(:one), actor: users(:two), notifiable: comment, action: "comment")

    comment.destroy

    assert_not Notification.exists?(explicit.id)
    assert_equal 0, Notification.where(notifiable_type: "Comment", notifiable_id: comment.id).count,
                 "no notification may outlive the comment it points at"
  end

  test "destroying a comment destroys its mention notifications" do
    card = cards(:one)
    comment = card.comments.create!(user: users(:two), content: "Hey @One")
    mention = Notification.create!(recipient: users(:one), actor: users(:two), notifiable: comment, action: "mention")

    comment.destroy

    assert_not Notification.exists?(mention.id)
    assert_equal 0, Notification.where(notifiable_type: "Comment", notifiable_id: comment.id).count
  end

  test "destroying a card takes its comments' notifications with it" do
    card = cards(:one)
    comment = card.comments.create!(user: users(:two), content: "Comment on a doomed card")
    on_comment = Notification.create!(recipient: users(:one), actor: users(:two), notifiable: comment, action: "comment")
    on_card    = Notification.create!(recipient: users(:one), actor: users(:two), notifiable: card, action: "added_to_card")

    card.destroy

    # The comment cascade has to fire as part of the card cascade, or destroying
    # a card leaves its comments' notifications orphaned even once Comment
    # declares its own.
    assert_not Notification.exists?(on_comment.id), "a comment's notification must not outlive the card"
    assert_not Notification.exists?(on_card.id)
    assert_equal 0, Notification.where(notifiable_type: "Comment", notifiable_id: comment.id).count
    assert_equal 0, Notification.where(notifiable_type: "Card", notifiable_id: card.id).count
  end

  test "destroying a card leaves another card's notifications alone" do
    card = cards(:one)
    other = cards(:two)
    Notification.create!(recipient: users(:one), actor: users(:two), notifiable: card, action: "added_to_card")
    keeper = Notification.create!(recipient: users(:two), actor: users(:one), notifiable: other, action: "added_to_card")

    card.destroy

    assert Notification.exists?(keeper.id), "an unrelated card's notification must survive"
  end
end
