require "test_helper"

class BoardUsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one) # owner of boards(:one)
    @board = boards(:one)
    sign_in @user
  end

  test "owner can add a member by email" do
    invitee = users(:two)

    assert_difference('BoardUser.count', 1) do
      post board_board_users_url(@board), params: { email: invitee.email }
    end
    assert_redirected_to edit_board_url(@board)
  end

  test "owner can remove a member" do
    membership = @board.board_users.create!(user: users(:two))

    assert_difference('BoardUser.count', -1) do
      delete board_board_user_url(@board, membership)
    end
    assert_redirected_to edit_board_url(@board)
  end

  test "a shared member cannot add other members" do
    member = User.create!(email: "member@example.com", password: "password")
    @board.board_users.create!(user: member)
    sign_out @user
    sign_in member

    assert_no_difference('BoardUser.count') do
      post board_board_users_url(@board), params: { email: users(:two).email }
    end
    assert_response :not_found
  end

  test "a shared member cannot remove other members" do
    member = User.create!(email: "member@example.com", password: "password")
    membership = @board.board_users.create!(user: member)
    other_membership = @board.board_users.create!(user: users(:two))
    sign_out @user
    sign_in member

    assert_no_difference('BoardUser.count') do
      delete board_board_user_url(@board, other_membership)
    end
    assert_response :not_found
  end

  test "owner cannot remove a membership row belonging to a different board" do
    other_board = boards(:two)
    foreign_membership = other_board.board_users.create!(user: users(:one))

    assert_no_difference('BoardUser.count') do
      delete board_board_user_url(@board, foreign_membership)
    end
    assert_response :not_found
  end
end
