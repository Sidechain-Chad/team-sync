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

  test "favorited_by? returns true if favorite exists" do
    user = User.create!(email: "fav@example.com", password: "password")
    board = Board.create!(name: "Fav Board", user: user)
    BoardFavorite.create!(board: board, user: user)
    assert board.favorited_by?(user)
  end

  test "favorited_by? returns false if favorite does not exist" do
    user = User.create!(email: "nofav@example.com", password: "password")
    board = Board.create!(name: "No Fav Board", user: user)
    assert_not board.favorited_by?(user)
  end

  test "invite_users adds matched addresses and returns the unmatched ones" do
    owner = User.create!(email: "owner@example.com", password: "password")
    board = Board.create!(name: "Invite Board", user: owner)
    real = User.create!(email: "real@example.com", password: "password")

    unmatched = board.invite_users("#{real.email}, ghost@example.com", owner)

    assert_includes board.board_users.map(&:user), real
    assert_equal ["ghost@example.com"], unmatched
  end

  test "invite_users returns an empty array when every address matches" do
    owner = User.create!(email: "owner2@example.com", password: "password")
    board = Board.create!(name: "Invite Board 2", user: owner)
    real = User.create!(email: "real2@example.com", password: "password")

    assert_empty board.invite_users(real.email, owner)
  end

  test "invite_users does not report the inviter's own email as unmatched" do
    owner = User.create!(email: "owner3@example.com", password: "password")
    board = Board.create!(name: "Invite Board 3", user: owner)

    assert_empty board.invite_users(owner.email, owner)
  end
end
