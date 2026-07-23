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
end
