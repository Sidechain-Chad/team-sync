require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "board_test@example.com", password: "password")
    @board = @user.boards.create!(name: "Test Board")
    sign_in @user
  end

  test "should toggle favorite via patch" do
    assert_difference "BoardFavorite.count", 1 do
      patch toggle_favorite_board_url(@board), as: :turbo_stream
    end
    assert_response :success
    assert @board.favorited_by?(@user)

    assert_difference "BoardFavorite.count", -1 do
      patch toggle_favorite_board_url(@board), as: :turbo_stream
    end
    assert_response :success
    assert_not @board.favorited_by?(@user)
  end
end
