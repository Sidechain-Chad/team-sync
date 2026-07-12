require "test_helper"

class PlannerControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "should get index" do
    get planner_url
    assert_response :success
  end

  test "should get index with year and month" do
    get planner_url(year: 2026, month: 4)
    assert_response :success
    assert_select "h1", "April 2026"
  end

  test "should handle invalid month" do
    get planner_url(year: 2026, month: 13)
    assert_response :success
  end

  test "should get map" do
    get planner_map_url
    assert_response :success
  end

  test "should get map with year and month" do
    get planner_map_url(year: 2026, month: 4)
    assert_response :success
    assert_select "h1", "April 2026"
  end

  test "should not show a dated card from a board the user has no access to" do
    other_card = cards(:two) # belongs to boards(:two), owned by users(:two)
    other_card.update!(title: "Unique Foreign Card Title 42", due_date: Date.current)

    get planner_url
    assert_response :success
    assert_no_match "Unique Foreign Card Title 42", response.body
  end

  test "should not show a located card from a board the user has no access to on the map" do
    other_card = cards(:two)
    other_card.update!(title: "Unique Foreign Card Title 43", due_date: Date.current, latitude: 1.0, longitude: 1.0)

    get planner_map_url
    assert_response :success
    assert_no_match "Unique Foreign Card Title 43", response.body
  end

  test "cannot widen the planner's board scope via a board_id-like param" do
    other_card = cards(:two)
    other_card.update!(title: "Unique Foreign Card Title 44", due_date: Date.current)

    get planner_url(board_id: other_card.list.board.id)
    assert_response :success
    assert_no_match "Unique Foreign Card Title 44", response.body
  end
end
