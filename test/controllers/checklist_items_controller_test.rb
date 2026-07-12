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
    assert_redirected_to board_url(@card.list.board)
  end

  test "should update checklist_item" do
    patch card_checklist_checklist_item_url(@card, @checklist, @checklist_item), params: { checklist_item: { completed: true } }
    assert_redirected_to board_url(@card.list.board)
    assert @checklist_item.reload.completed
  end

  test "should destroy checklist_item" do
    assert_difference('ChecklistItem.count', -1) do
      delete card_checklist_checklist_item_url(@card, @checklist, @checklist_item)
    end
    assert_redirected_to board_url(@card.list.board)
  end

  test "should not create checklist_item on a checklist the user has no access to" do
    other_card = cards(:two)
    other_checklist = checklists(:two)

    assert_no_difference('ChecklistItem.count') do
      post card_checklist_checklist_items_url(other_card, other_checklist), params: { checklist_item: { content: 'Injected' } }
    end
    assert_response :not_found
  end

  test "should not update a checklist_item belonging to a checklist the user has no access to" do
    other_card = cards(:two)
    other_checklist = checklists(:two)
    other_item = checklist_items(:two)

    patch card_checklist_checklist_item_url(other_card, other_checklist, other_item), params: { checklist_item: { completed: true } }

    assert_response :not_found
    assert_not other_item.reload.completed
  end

  test "should not destroy a checklist_item id that belongs to a different checklist than the one in the path" do
    foreign_item = checklist_items(:two) # belongs to checklists(:two)

    assert_no_difference('ChecklistItem.count') do
      delete card_checklist_checklist_item_url(@card, @checklist, foreign_item)
    end
    assert_response :not_found
  end
end
