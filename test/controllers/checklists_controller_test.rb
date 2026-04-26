require "test_helper"

class ChecklistsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @card = cards(:one)
    @checklist = checklists(:one)
    sign_in @user
  end

  test "should create checklist" do
    assert_difference('Checklist.count') do
      post card_checklists_url(@card), params: { checklist: { title: 'New Checklist' } }
    end
    assert_redirected_to board_url(@card.list.board)
  end

  test "should destroy checklist" do
    assert_difference('Checklist.count', -1) do
      delete card_checklist_url(@card, @checklist)
    end
    assert_redirected_to board_url(@card.list.board)
  end
end
