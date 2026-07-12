require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board = boards(:one)
    @list = lists(:one)
    sign_in @user
  end

  test "should create list" do
    assert_difference('List.count') do
      post board_lists_url(@board), params: { list: { name: 'New List' } }
    end
    assert_redirected_to board_url(@board)
  end

  test "should not create list on a board the user has no access to" do
    other_board = boards(:two)

    assert_no_difference('List.count') do
      post board_lists_url(other_board), params: { list: { name: 'Injected List' } }
    end

    assert_response :not_found
  end

  test "should move list within its board" do
    list_two = @board.lists.create!(name: "List Two")

    patch move_list_url(list_two), params: { list: { position: 1 } }

    assert_response :success
    assert_equal 1, list_two.reload.position
    assert_equal 2, @list.reload.position
  end

  test "should not move a list belonging to another user's board" do
    other_list = lists(:two)

    patch move_list_url(other_list), params: { list: { position: 1 } }

    assert_response :not_found
  end
end
