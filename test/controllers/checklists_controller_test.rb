require "test_helper"

class ChecklistsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get checklists_create_url
    assert_response :success
  end

  test "should get update" do
    get checklists_update_url
    assert_response :success
  end

  test "should get destroy" do
    get checklists_destroy_url
    assert_response :success
  end
end
