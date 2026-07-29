require "test_helper"

class CardMembersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

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

  # --- board-tile broadcast ---
  #
  # A card's assigned members show as avatars on its board tile, so adding or
  # removing one changes what every viewer of the board sees. CardLabelsController
  # — the exact sibling of this controller, same UI surface — already broadcasts
  # the re-rendered card tile for the same reason; this was simply missed.
  #
  # No double-render risk: the actor's own turbo_stream template touches only
  # modal-internal frames (member_row_*, assigned_members_list,
  # card_face_avatars_*), never the board tile — and `replace` targets by id, so
  # it's idempotent even if it ever did.

  test "adding a member broadcasts the re-rendered card tile to the board" do
    other = users(:two)
    @board.board_users.create!(user: other) unless @board.active_members.include?(other)
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      post card_members_url(@card), params: { user_id: other.id }, as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
  end

  test "removing a member broadcasts the re-rendered card tile to the board" do
    other = users(:two)
    @board.board_users.create!(user: other) unless @board.active_members.include?(other)
    @card.members << other
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      delete card_member_url(@card, other), as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
  end

  test "the actor's own response does not contain the board tile (anti double-render)" do
    other = users(:two)
    @board.board_users.create!(user: other) unless @board.active_members.include?(other)

    post card_members_url(@card), params: { user_id: other.id }, as: :turbo_stream

    assert_response :success
    assert_no_match(/target="#{ActionView::RecordIdentifier.dom_id(@card)}"/, response.body)
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
