require "test_helper"

class LabelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board = boards(:one)
    @card = cards(:one) # belongs to @board; label views need card_id in context
    @label = labels(:one)
    sign_in @user
  end

  test "should create label on own board" do
    assert_difference('Label.count', 1) do
      post board_labels_url(@board), params: { label: { color: "red" }, card_id: @card.id }, as: :turbo_stream
    end
    assert_response :success
  end

  test "should not create label on a board the user has no access to" do
    other_board = boards(:two)

    assert_no_difference('Label.count') do
      post board_labels_url(other_board), params: { label: { color: "red" }, card_id: @card.id }, as: :turbo_stream
    end
    assert_response :not_found
  end

  test "should not update a label on a board the user has no access to" do
    other_board = boards(:two)
    other_label = other_board.labels.create!(color: "orange")

    patch board_label_url(other_board, other_label), params: { label: { color: "black" }, card_id: @card.id }, as: :turbo_stream

    assert_response :not_found
    assert_equal "orange", other_label.reload.color
  end

  test "should not destroy a label on a board the user has no access to" do
    other_board = boards(:two)
    other_label = other_board.labels.create!(color: "orange")

    assert_no_difference('Label.count') do
      delete board_label_url(other_board, other_label), as: :turbo_stream
    end
    assert_response :not_found
  end

  test "should not leak a foreign card via an injected card_id param on create" do
    foreign_card = cards(:two) # belongs to boards(:two), owned by users(:two)

    post board_labels_url(@board), params: { label: { color: "red" }, card_id: foreign_card.id }, as: :turbo_stream

    assert_response :not_found
  end

  test "should not destroy a label id that belongs to a different board than the one in the path" do
    # Path board is accessible, but the label id belongs to another board —
    # set_label chains off @board.labels, so this should 404 rather than
    # destroying a foreign board's label.
    foreign_label = boards(:two).labels.create!(color: "orange")

    assert_no_difference('Label.count') do
      delete board_label_url(@board, foreign_label), as: :turbo_stream
    end
    assert_response :not_found
  end

  test "label update broadcast query count stays flat as card count grows" do
    small = count_queries_for_label_update(cards_with_label: 5)
    large = count_queries_for_label_update(cards_with_label: 10)

    assert_operator small, :<=, 15
    assert_equal small, large, "query count must not grow with card count (N+1 regression)"
  end

  test "label destroy broadcast query count stays flat as card count grows" do
    small = count_queries_for_label_destroy(card_count: 5)
    large = count_queries_for_label_destroy(card_count: 10)

    assert_operator small, :<=, 15
    assert_equal small, large, "query count must not grow with card count (N+1 regression)"
  end

  private

  def count_queries_for_label_update(cards_with_label:)
    user = User.create!(email: "label_update_perf#{cards_with_label}@example.com", password: "password")
    sign_in user

    board = user.boards.create!(name: "Label Update Perf Board #{cards_with_label}")
    list = board.lists.create!(name: "List", position: 1)
    label = board.labels.create!(color: "red")

    cards = Array.new(cards_with_label) do |i|
      card = list.cards.create!(title: "Card #{i}")
      card.labels << label
      card
    end

    result = count_queries do
      patch board_label_url(board, label),
            params: { label: { color: "blue" }, card_id: cards.first.id },
            as: :turbo_stream
    end
    assert_response :success
    sign_out user
    result
  end

  def count_queries_for_label_destroy(card_count:)
    user = User.create!(email: "label_destroy_perf#{card_count}@example.com", password: "password")
    sign_in user

    board = user.boards.create!(name: "Label Destroy Perf Board #{card_count}")
    list = board.lists.create!(name: "List", position: 1)
    label = board.labels.create!(color: "red")

    # Keep the labeled subset fixed at 2 regardless of card_count — Label
    # has_many :card_labels, dependent: :destroy issues one DELETE per join
    # row, which is a separate pre-existing N+1 unrelated to the broadcast
    # this test targets. Scaling it here would conflate the two.
    card_count.times do |i|
      card = list.cards.create!(title: "Card #{i}")
      card.labels << label if i < 2
    end

    result = count_queries do
      delete board_label_url(board, label), as: :turbo_stream
    end
    assert_response :success
    sign_out user
    result
  end
end
