require "test_helper"

class CardWatcherTest < ActiveSupport::TestCase
  setup do
    @card = cards(:one)
    @user = users(:one)
  end

  test "watching a card creates the join row and both associations resolve" do
    assert_difference "CardWatcher.count", 1 do
      CardWatcher.create!(card: @card, user: @user)
    end

    assert_includes @card.reload.watchers, @user
    assert_includes @user.reload.watched_cards, @card
  end

  test "unwatching destroys the join row" do
    CardWatcher.create!(card: @card, user: @user)

    assert_difference "CardWatcher.count", -1 do
      @user.card_watchers.find_by(card: @card).destroy
    end

    assert_not_includes @card.reload.watchers, @user
  end

  test "watching the same card twice is rejected by the validation" do
    CardWatcher.create!(card: @card, user: @user)

    duplicate = CardWatcher.new(card: @card, user: @user)

    assert_not duplicate.valid?
    assert_no_difference "CardWatcher.count" do
      assert_not duplicate.save
    end
  end

  # The validation above races; the index is what actually holds. Insert straight
  # through the connection so the validation can't be what rejects it — this
  # asserts the DB constraint exists, not the model's opinion of it.
  test "a duplicate watch is impossible at the DATABASE level" do
    CardWatcher.create!(card: @card, user: @user)

    assert_raises(ActiveRecord::RecordNotUnique) do
      CardWatcher.connection.execute(
        "INSERT INTO card_watchers (card_id, user_id, created_at, updated_at) " \
        "VALUES (#{@card.id}, #{@user.id}, NOW(), NOW())"
      )
    end
  end

  test "the same user can watch two different cards" do
    CardWatcher.create!(card: @card, user: @user)

    assert_difference "CardWatcher.count", 1 do
      CardWatcher.create!(card: cards(:two), user: @user)
    end
  end

  test "destroying a card destroys its watches" do
    CardWatcher.create!(card: @card, user: @user)

    assert_difference "CardWatcher.count", -1 do
      @card.destroy
    end
  end

  test "destroying a user destroys their watches" do
    user = User.create!(email: "watcher-destroy@example.com", password: "password")
    CardWatcher.create!(card: @card, user: user)

    assert_difference "CardWatcher.count", -1 do
      user.destroy
    end
  end

  # Watching is current state, not history — same category as card_members, which
  # deactivate! already strips. Otherwise a deactivated account keeps accruing
  # comment and due_soon notifications for everything it was watching.
  test "deactivating a user stops their watching" do
    user = User.create!(email: "watcher-deactivate@example.com", password: "password")
    CardWatcher.create!(card: @card, user: user)

    user.deactivate!

    assert_empty user.reload.card_watchers
    assert_not_includes @card.reload.watchers, user
  end
end
