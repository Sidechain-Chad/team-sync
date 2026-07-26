require "test_helper"

class PlannerControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "should get index" do
    get planner_url
    assert_response :success
  end

  test "should get index with year and month" do
    get planner_url(year: 2026, month: 4)
    assert_response :success
    assert_select "h1", "April 2026"
  end

  test "should handle invalid month" do
    get planner_url(year: 2026, month: 13)
    assert_response :success
  end

  test "should get map" do
    get planner_map_url
    assert_response :success
  end

  test "should get map with year and month" do
    get planner_map_url(year: 2026, month: 4)
    assert_response :success
    assert_select "h1", "April 2026"
  end

  test "should not show a dated card from a board the user has no access to" do
    other_card = cards(:two) # belongs to boards(:two), owned by users(:two)
    other_card.update!(title: "Unique Foreign Card Title 42", due_date: Date.current)

    get planner_url
    assert_response :success
    assert_no_match "Unique Foreign Card Title 42", response.body
  end

  test "should not show a located card from a board the user has no access to on the map" do
    other_card = cards(:two)
    other_card.update!(title: "Unique Foreign Card Title 43", due_date: Date.current, latitude: 1.0, longitude: 1.0)

    get planner_map_url
    assert_response :success
    assert_no_match "Unique Foreign Card Title 43", response.body
  end

  # --- start_date ranges: bars vs points ---

  test "a card with only a due date renders a single point on its due day" do
    card = cards(:one)
    day = Date.new(2026, 5, 6)
    card.update!(title: "Point Card 51", start_date: nil, due_date: day.to_time.change(hour: 9))

    get planner_url(year: 2026, month: 5)

    assert_response :success
    assert_equal 1, chip_count_for(card)
    assert_no_match(/data-planner-segment/, response.body)
  end

  test "a card with both dates renders a bar segment on every day it spans" do
    card = cards(:one)
    card.update!(title: "Range Card 52",
                 start_date: Date.new(2026, 5, 4).to_time.change(hour: 9),
                 due_date:   Date.new(2026, 5, 6).to_time.change(hour: 17))

    get planner_url(year: 2026, month: 5)

    assert_response :success
    assert_equal 3, chip_count_for(card), "expected one segment per spanned day"
    assert_match(/data-planner-segment="start"/, response.body)
    assert_match(/data-planner-segment="middle"/, response.body)
    assert_match(/data-planner-segment="end"/, response.body)
  end

  test "a same-day start and due renders as a point, not a one-segment bar" do
    card = cards(:one)
    day = Date.new(2026, 5, 6)
    card.update!(title: "Same Day Card 53",
                 start_date: day.to_time.change(hour: 9),
                 due_date:   day.to_time.change(hour: 17))

    get planner_url(year: 2026, month: 5)

    assert_response :success
    assert_equal 1, chip_count_for(card)
    assert_no_match(/data-planner-segment/, response.body)
  end

  test "a range that starts before the visible month still renders its in-month days" do
    card = cards(:one)
    card.update!(title: "Spillover Card 54",
                 start_date: Date.new(2026, 4, 20).to_time,
                 due_date:   Date.new(2026, 5, 2).to_time)

    get planner_url(year: 2026, month: 5)

    assert_response :success
    # The May grid starts on Sun Apr 26, so Apr 26–30 plus May 1–2 are visible.
    assert_operator chip_count_for(card), :>=, 2
  end

  test "a card with a start date but no due date does not appear on the planner" do
    card = cards(:one)
    card.update!(title: "Start Only Card 55", due_date: nil, start_date: Date.new(2026, 5, 6).to_time)

    get planner_url(year: 2026, month: 5)

    assert_response :success
    assert_no_match "Start Only Card 55", response.body
  end

  test "a range card from an inaccessible board still never appears" do
    other_card = cards(:two)
    other_card.update!(title: "Foreign Range Card 56",
                       start_date: Date.new(2026, 5, 4).to_time,
                       due_date:   Date.new(2026, 5, 6).to_time)

    get planner_url(year: 2026, month: 5)

    assert_response :success
    assert_no_match "Foreign Range Card 56", response.body
  end

  test "planner query count stays flat as the number of range cards grows" do
    small = count_queries_for_planner(range_cards: 3)
    large = count_queries_for_planner(range_cards: 6)

    assert_equal small, large, "query count must not grow with card count (N+1 regression)"
  end

  test "cannot widen the planner's board scope via a board_id-like param" do
    other_card = cards(:two)
    other_card.update!(title: "Unique Foreign Card Title 44", due_date: Date.current)

    get planner_url(board_id: other_card.list.board.id)
    assert_response :success
    assert_no_match "Unique Foreign Card Title 44", response.body
  end

  private

  # Counts rendered chips/bar-segments for a card, by its link href. Counting
  # the title string instead would double-count: the title also appears in each
  # link's own title= attribute.
  def chip_count_for(card)
    response.body.scan(/href="#{Regexp.escape(card_path(card))}"/).size
  end

  def count_queries_for_planner(range_cards:)
    user = User.create!(email: "plannerperf#{range_cards}@example.com", password: "password")
    sign_in user

    board = user.boards.create!(name: "Planner Perf Board #{range_cards}")
    board.lists.destroy_all
    list = board.lists.create!(name: "List", position: 1)

    range_cards.times do |i|
      list.cards.create!(
        title: "Range #{i}",
        start_date: Date.new(2026, 5, 4).to_time,
        due_date:   Date.new(2026, 5, 6).to_time
      )
    end

    result = count_queries { get planner_url(year: 2026, month: 5) }
    assert_response :success
    sign_out user
    result
  end
end
