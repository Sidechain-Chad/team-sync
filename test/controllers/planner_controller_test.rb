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
end
