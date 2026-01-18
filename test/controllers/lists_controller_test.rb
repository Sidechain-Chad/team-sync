require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get lists_create_url
    assert_response :success
  end
end
