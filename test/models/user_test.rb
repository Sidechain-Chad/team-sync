require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "deactivate! sets deactivated_at and clears memberships" do
    user = users(:one)
    board = boards(:one)
    card = cards(:one)
    
    # Ensure they are members
    BoardUser.find_or_create_by!(board: board, user: user)
    CardMember.find_or_create_by!(card: card, user: user)
    
    assert_nil user.deactivated_at
    assert_not_empty user.board_users
    assert_not_empty user.card_members
    
    user.deactivate!
    
    assert_not_nil user.deactivated_at
    assert_empty user.board_users
    assert_empty user.card_members
  end

  test "active_for_authentication? returns false when deactivated" do
    user = users(:one)
    assert user.active_for_authentication?
    
    user.deactivate!
    assert_not user.active_for_authentication?
  end
  
  test "display_name includes deactivated marker" do
    user = users(:one)
    name = user.name
    assert_equal name, user.display_name
    
    user.deactivate!
    assert_equal "#{name} (deactivated)", user.display_name
  end
end
