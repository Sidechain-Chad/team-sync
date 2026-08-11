require "test_helper"

class BoardWatcherTest < ActiveSupport::TestCase
  setup do
    @board = boards(:one)
    @user = users(:one)
  end

  test "watching a board creates the join row and both associations resolve" do
    assert_difference "BoardWatcher.count", 1 do
      BoardWatcher.create!(board: @board, user: @user)
    end

    assert_includes @board.reload.watchers, @user
    assert_includes @user.reload.watched_boards, @board
  end

  test "unwatching destroys the join row" do
    BoardWatcher.create!(board: @board, user: @user)

    assert_difference "BoardWatcher.count", -1 do
      @user.board_watchers.find_by(board: @board).destroy
    end

    assert_not_includes @board.reload.watchers, @user
  end

  test "watching the same board twice is rejected by the validation" do
    BoardWatcher.create!(board: @board, user: @user)

    duplicate = BoardWatcher.new(board: @board, user: @user)

    assert_not duplicate.valid?
    assert_no_difference "BoardWatcher.count" do
      assert_not duplicate.save
    end
  end

  # The validation above races; the index is what actually holds. Insert straight
  # through the connection so the validation can't be what rejects it — this
  # asserts the DB constraint exists, not the model's opinion of it.
  test "a duplicate watch is impossible at the DATABASE level" do
    BoardWatcher.create!(board: @board, user: @user)

    assert_raises(ActiveRecord::RecordNotUnique) do
      BoardWatcher.connection.execute(
        "INSERT INTO board_watchers (board_id, user_id, created_at, updated_at) " \
        "VALUES (#{@board.id}, #{@user.id}, NOW(), NOW())"
      )
    end
  end

  test "the same user can watch two different boards" do
    BoardWatcher.create!(board: @board, user: @user)

    assert_difference "BoardWatcher.count", 1 do
      BoardWatcher.create!(board: boards(:two), user: @user)
    end
  end

  test "destroying a board destroys its watches" do
    BoardWatcher.create!(board: @board, user: @user)

    assert_difference "BoardWatcher.count", -1 do
      @board.destroy
    end
  end

  test "destroying a user destroys their watches" do
    user = User.create!(email: "board-watcher-destroy@example.com", password: "password")
    BoardWatcher.create!(board: @board, user: user)

    assert_difference "BoardWatcher.count", -1 do
      user.destroy
    end
  end

  # Watching is current state, not history — same category as card_watchers,
  # which deactivate! already strips. Otherwise a deactivated account keeps
  # accruing notifications for every board it watched.
  test "deactivating a user stops their watching" do
    user = User.create!(email: "board-watcher-deactivate@example.com", password: "password")
    BoardWatcher.create!(board: @board, user: user)

    user.deactivate!

    assert_empty user.reload.board_watchers
    assert_not_includes @board.reload.watchers, user
  end
end
