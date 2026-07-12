require "test_helper"

class CardMembersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board = boards(:one)
    @card = cards(:one)
    sign_in @user
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
