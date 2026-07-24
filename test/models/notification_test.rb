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
end
