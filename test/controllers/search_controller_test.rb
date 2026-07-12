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
