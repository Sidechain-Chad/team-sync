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

  test "should not create checklist on a card the user has no access to" do
    other_card = cards(:two)

    assert_no_difference('Checklist.count') do
      post card_checklists_url(other_card), params: { checklist: { title: 'Injected' } }
    end
    assert_response :not_found
  end

  test "should not destroy a checklist belonging to a card the user has no access to" do
    other_card = cards(:two)
    other_checklist = checklists(:two)

    assert_no_difference('Checklist.count') do
      delete card_checklist_url(other_card, other_checklist)
    end
    assert_response :not_found
  end

  test "should not destroy a checklist id that belongs to a different card than the one in the path" do
    foreign_checklist = checklists(:two) # belongs to cards(:two)

    assert_no_difference('Checklist.count') do
      delete card_checklist_url(@card, foreign_checklist)
    end
    assert_response :not_found
  end
end
