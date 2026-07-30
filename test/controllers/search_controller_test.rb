require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board = boards(:one)
    @card = cards(:one)
    sign_in @user
  end

  test "should get index" do
    get search_url
    assert_response :success
    assert_select "turbo-frame#search_results"
  end

  # --- closed boards are unsearchable, and so are their cards ---
  #
  # Search is the most direct way a hidden board would leak back into view: by
  # name, or via any card on it. Both sides go through open_boards/open_cards.

  # The results partial wraps the matched term in <mark>, so the full name/title
  # is never a contiguous string in the body. These assert on the un-highlighted
  # tail word instead, which is present or absent as a whole either way.
  test "a closed board is absent from board search results" do
    board = @user.boards.create!(name: "Zubrowka Distinctive Board")

    get search_url(q: "Zubrowka")
    assert_response :success
    assert_match "Distinctive Board", response.body

    board.close!
    get search_url(q: "Zubrowka")

    assert_response :success
    assert_no_match(/Distinctive Board/, response.body)
  end

  test "a card on a closed board is absent from card search results" do
    board = @user.boards.create!(name: "Quixotic Holder Board")
    list = board.lists.create!(name: "L", position: 1)
    card = list.cards.create!(title: "Zaphodica Findable Card", position: 1)
    assert card.persisted?

    get search_url(q: "Zaphodica")
    assert_response :success
    assert_match "Findable Card", response.body

    board.close!
    get search_url(q: "Zaphodica")

    assert_response :success
    assert_no_match(/Findable Card/, response.body)
  end

  test "a closed board is absent from the blank-query recent boards list" do
    board = @user.boards.create!(name: "Yggdrasil Recent Board")

    # The blank-query branch isn't highlighted, so the full name matches here.
    get search_url(q: "")
    assert_response :success
    assert_match board.name, response.body

    board.close!
    get search_url(q: "")

    assert_response :success
    assert_no_match(/Yggdrasil Recent Board/, response.body)
  end

  test "should get search results for boards" do
    get search_url(q: @board.name)
    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_match @board.name, response.body
  end

  test "should get search results for cards" do
    get search_url(q: @card.title)
    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_match @card.title, response.body
  end

  test "should return no results message" do
    get search_url(q: "NonExistentThing123456789")
    assert_response :success
    assert_match "No matches for", response.body
  end

  test "should not return a board the user has no access to" do
    other_board = boards(:two)
    other_board.update!(name: "Unique Foreign Board For Search 99")

    get search_url(q: "Unique Foreign Board For Search 99")

    assert_response :success
    # Confirms zero results — the board exists with this exact name, so a
    # hit here would mean the scope leaked, not that pg_search missed it.
    assert_match "No matches for", response.body
  end

  test "should not return a card the user has no access to" do
    other_card = cards(:two)
    other_card.update!(title: "Unique Foreign Card For Search 99")

    get search_url(q: "Unique Foreign Card For Search 99")

    assert_response :success
    assert_match "No matches for", response.body
  end
end
