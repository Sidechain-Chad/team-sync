require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "board_test@example.com", password: "password")
    @board = @user.boards.create!(name: "Test Board")
    sign_in @user
  end

  test "should toggle favorite via patch" do
    assert_nil @board.favorited_at

    patch toggle_favorite_board_url(@board), as: :turbo_stream
    assert_response :success
    @board.reload
    assert_not_nil @board.favorited_at

    patch toggle_favorite_board_url(@board), as: :turbo_stream
    assert_response :success
    @board.reload
    assert_nil @board.favorited_at
  end
end
