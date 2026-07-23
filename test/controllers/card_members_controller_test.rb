require "test_helper"

class CardMembersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board = boards(:one)
    @card = cards(:one)
    sign_in @user

    # Notification.deliver's after_create_commit broadcasts via a Turbo
    # Streams job — see NotificationTest for why this needs the :test
    # adapter under transactional fixtures + the app's default :async adapter.
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "should add a board member as a card member" do
    member = users(:two)
    @board.board_users.create!(user: member)

    assert_difference('CardMember.count', 1) do
      post card_members_url(@card, user_id: member.id), as: :turbo_stream
    end
    assert_response :success
    assert_includes @card.reload.members, member
  end

  test "adding another user as a card member notifies them, with the adder as actor" do
    member = users(:two)
    @board.board_users.create!(user: member)

    assert_difference "Notification.count", 1 do
      post card_members_url(@card, user_id: member.id), as: :turbo_stream
    end

    notification = Notification.last
    assert_equal member, notification.recipient
    assert_equal @user, notification.actor
    assert_equal "added_to_card", notification.action
  end

  test "adding yourself as a card member creates no notification" do
    # @user is already the board owner and already a card member (fixtures),
    # so this exercises deliver's self-notify no-op even though the
    # membership add itself is a harmless idempotent no-op too.
    assert_no_difference "Notification.count" do
      post card_members_url(@card, user_id: @user.id), as: :turbo_stream
    end
  end

  test "should not add an arbitrary user with no board access as a card member" do
    outsider = users(:two)

    assert_no_difference('CardMember.count') do
      post card_members_url(@card, user_id: outsider.id), as: :turbo_stream
    end

    assert_response :not_found
    assert_not_includes @card.reload.members, outsider
  end

  test "should remove a card member" do
    member = users(:two)
    @board.board_users.create!(user: member)
    @card.members << member

    assert_difference('CardMember.count', -1) do
      delete card_member_url(@card, user_id: member.id), as: :turbo_stream
    end
    assert_response :success
    assert_not_includes @card.reload.members, member
  end
end
