require "test_helper"

class BoardTest < ActiveSupport::TestCase
  test "should seed default lists after creation" do
    user = User.create!(email: "test@example.com", password: "password")
    board = Board.create!(name: "New Board", user: user)

    assert_equal 3, board.lists.count
    assert_equal ["To Do", "Doing", "Done"], board.lists.order(:position).pluck(:name)
  end

  test "should seed default labels after creation" do
    user = User.create!(email: "test2@example.com", password: "password")
    board = Board.create!(name: "Another Board", user: user)

    assert_not_empty board.labels
    assert_equal Label::COLORS.count, board.labels.count
  end
end
