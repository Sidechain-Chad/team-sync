require "test_helper"

class ChecklistItemsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get checklist_items_create_url
    assert_response :success
  end

  test "should get update" do
    get checklist_items_update_url
    assert_response :success
  end

  test "should get destroy" do
    get checklist_items_destroy_url
    assert_response :success
  end
end
