require "test_helper"

class ListTest < ActiveSupport::TestCase
  setup do
    @board = boards(:one)
    @list = @board.lists.create!(name: "WIP List")
  end

  # --- card_limit (soft WIP limit) ---

  test "card_limit is nil by default, which means no limit" do
    assert_nil @list.card_limit
    assert_not @list.card_limit?
    assert_not @list.over_card_limit?
  end

  test "card_limit accepts a positive integer" do
    @list.card_limit = 3
    assert @list.valid?
    @list.save!
    assert_equal 3, @list.reload.card_limit
    assert @list.card_limit?
  end

  test "card_limit rejects zero and negative values" do
    [0, -1].each do |bad|
      @list.card_limit = bad
      assert_not @list.valid?, "expected #{bad} to be invalid"
      assert_includes @list.errors[:card_limit].join, "greater than 0"
    end
  end

  test "card_limit rejects a non-integer" do
    @list.card_limit = 2.5
    assert_not @list.valid?
  end

  test "card_limit can be cleared back to nil" do
    @list.update!(card_limit: 4)
    @list.update!(card_limit: nil)
    assert_nil @list.reload.card_limit
    assert_not @list.card_limit?
  end

  test "over_card_limit? is true only when active cards exceed the limit" do
    3.times { |i| @list.cards.create!(title: "Card #{i}") }

    @list.update!(card_limit: 3)
    assert_not @list.reload.over_card_limit?, "at the limit is not over it"

    @list.update!(card_limit: 2)
    assert @list.reload.over_card_limit?
  end

  test "over_card_limit? counts only active cards, not archived ones" do
    3.times { |i| @list.cards.create!(title: "Card #{i}") }
    @list.update!(card_limit: 2)
    assert @list.reload.over_card_limit?

    @list.cards.order(:position).first.archive!
    assert_not @list.reload.over_card_limit?
  end
end
