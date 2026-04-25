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
end
