require "test_helper"

class ChecklistItemsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @card = cards(:one)
    @checklist = checklists(:one)
    @checklist_item = checklist_items(:one)
    sign_in @user
  end

  test "should create checklist_item" do
    assert_difference('ChecklistItem.count') do
      post card_checklist_checklist_items_url(@card, @checklist), params: { checklist_item: { content: 'New Item' } }
    end
    assert_redirected_to card_url(@card)
  end

  test "should update checklist_item" do
    patch card_checklist_checklist_item_url(@card, @checklist, @checklist_item), params: { checklist_item: { completed: true } }
    assert_redirected_to card_url(@card)
    assert @checklist_item.reload.completed
  end

  test "should destroy checklist_item" do
    assert_difference('ChecklistItem.count', -1) do
      delete card_checklist_checklist_item_url(@card, @checklist, @checklist_item)
    end
    assert_redirected_to card_url(@card)
  end
end
