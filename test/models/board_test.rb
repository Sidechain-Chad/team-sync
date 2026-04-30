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

  test "favorited? returns true if favorited_at is present" do
    board = Board.new(favorited_at: Time.current)
    assert board.favorited?
  end

  test "favorited? returns false if favorited_at is nil" do
    board = Board.new(favorited_at: nil)
    assert_not board.favorited?
  end
end
