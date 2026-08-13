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

  # --- cards on a closed board are absent from every planner aggregation ---
  #
  # The grid, the agenda panel and the map are three separate queries over
  # current_user.open_lists. One test each, deliberately: they're the call sites
  # where a missed closed-board filter would hide, and a single combined test
  # would pass while two of the three still leaked.

  # A dated, located card on its own board, so its title can't collide with a
  # fixture. Due tomorrow: inside the current month's grid, inside the agenda's
  # 21-day window, and inside the map's month range.
  def closable_board_with_dated_card(title)
    board = @user.boards.create!(name: "Planner Closable #{title}")
    list  = board.lists.create!(name: "L", position: 1)
    card  = list.cards.create!(
      title: title,
      position: 1,
      due_date: Date.current.tomorrow.noon,
      location_name: "Somewhere",
      latitude: 51.5,
      longitude: -0.12
    )
    [board, card]
  end

  test "a card on a closed board is absent from the planner grid" do
    board, card = closable_board_with_dated_card("Grimsby Grid Card")

    get planner_url
    assert_response :success
    assert_match card.title, response.body

    board.close!
    get planner_url

    assert_response :success
    assert_no_match card.title, response.body
  end

  test "a card on a closed board is absent from the planner agenda panel" do
    board, card = closable_board_with_dated_card("Grimsby Agenda Card")

    get planner_panel_url
    assert_response :success
    assert_match card.title, response.body

    board.close!
    get planner_panel_url

    assert_response :success
    assert_no_match card.title, response.body
  end

  test "a card on a closed board is absent from the map" do
    board, card = closable_board_with_dated_card("Grimsby Map Card")

    get planner_map_url
    assert_response :success
    assert_match card.title, response.body

    board.close!
    get planner_map_url

    assert_response :success
    assert_no_match card.title, response.body
  end

  test "a closed board is not offered as the planner's back-to-board link" do
    board, _card = closable_board_with_dated_card("Grimsby Back Link Card")

    get board_url(board) # seeds session[:last_board_id]
    get planner_url
    assert_response :success
    assert_select "a[href=?]", board_path(board), minimum: 1

    board.close!
    get planner_url

    assert_response :success
    assert_select "a[href=?]", board_path(board), count: 0
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

  # --- side panel (21-day agenda) honours date ranges, same as the grid ---
  #
  # The agenda answers "what's on my plate on day X", so in-progress work belongs
  # on every day it spans. Reuses Card#planner_days rather than a second
  # day-expansion, so the panel and the calendar grid can't drift apart.

  # Repointed when the agenda began collapsing long ranges. Original intent — a
  # range card appears on more than one day, keyed to the right days — is kept; the
  # days are now its start and due rather than every day between.
  test "panel: a range card appears on its start and due day groups" do
    card = cards(:one)
    card.update!(title: "Panel Range Card 61",
                 start_date: Date.current.to_time.change(hour: 9),
                 due_date:   (Date.current + 2.days).to_time.change(hour: 17))

    get planner_panel_url

    assert_response :success
    assert_equal 2, chip_count_for(card)
    assert_equal [Date.current, Date.current + 2.days], panel_days_for(card)
  end

  test "panel: a card with only a due date appears once, on its due day" do
    card = cards(:one)
    card.update!(title: "Panel Point Card 62",
                 start_date: nil,
                 due_date: (Date.current + 3.days).to_time.change(hour: 9))

    get planner_panel_url

    assert_response :success
    assert_equal 1, chip_count_for(card)
    assert_equal [Date.current + 3.days], panel_days_for(card)
  end

  test "panel: a range extending past the window edge appears only for in-window days" do
    card = cards(:one)
    # Starts inside the 21-day window, ends well past it.
    card.update!(title: "Panel Spill Card 63",
                 start_date: (Date.current + 19.days).to_time.change(hour: 9),
                 due_date:   (Date.current + 30.days).to_time.change(hour: 17))

    get planner_panel_url

    assert_response :success
    # The window is today..today+21, so the due day (today+30) is outside it and
    # drops — which is what this test pins. Collapsing removes the intervening
    # days as well, and today isn't inside the span, so the start day is all that
    # remains.
    assert_equal [Date.current + 19.days], panel_days_for(card)
  end

  test "panel: a range that began before today shows only from today onward" do
    card = cards(:one)
    card.update!(title: "Panel Past Start Card 64",
                 start_date: (Date.current - 5.days).to_time.change(hour: 9),
                 due_date:   (Date.current + 1.day).to_time.change(hour: 17))

    get planner_panel_url

    assert_response :success
    assert_equal [Date.current, Date.current + 1.day], panel_days_for(card),
                 "the agenda starts today; earlier spanned days are out of the window"
  end

  test "panel: day groups stay in ascending order" do
    early = cards(:one)
    early.update!(title: "Panel Early 65", start_date: nil, due_date: (Date.current + 1.day).to_time.change(hour: 9))
    late = early.list.cards.create!(title: "Panel Late 66", due_date: (Date.current + 10.days).to_time.change(hour: 9))

    get planner_panel_url

    assert_response :success
    assert_operator response.body.index("Panel Early 65"), :<,
                    response.body.index("Panel Late 66"),
                    "agenda must read soonest-first"
  end

  test "panel: a range card from an inaccessible board never appears" do
    other_card = cards(:two)
    other_card.update!(title: "Panel Foreign Range 67",
                       start_date: (Date.current + 1.day).to_time.change(hour: 9),
                       due_date:   (Date.current + 3.days).to_time.change(hour: 17))

    get planner_panel_url

    assert_response :success
    assert_no_match "Panel Foreign Range 67", response.body
  end

  # --- agenda rows name their span, so repeated range rows are self-explanatory ---
  #
  # A range card appears on every day it spans, and every row was previously
  # identical (same title, same board, same due time) — it read as three separate
  # cards rather than one spanning one. Range rows now carry the span instead of
  # the bare due time. Due-only cards are untouched.

  test "panel: a range card's row shows the span instead of the due time" do
    card = cards(:one)
    card.update!(title: "Span Row Card 71",
                 start_date: Time.utc(2026, 8, 3, 9, 0),
                 due_date:   Time.utc(2026, 8, 5, 15, 0))
    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      # Two rows now, not three: today (Aug 1) is outside this span, so the agenda
      # shows only its start and due days. The point of this test is unchanged —
      # every range row carries the span rather than a bare time.
      assert_equal 2, chip_count_for(card)
      assert_equal 2, response.body.scan("Aug 3–5").size
      # ...and none of them shows the bare due time any more.
      assert_no_match(/3:00 PM/, response.body)
    end
  end

  test "panel: a due-only card's row still shows its time, unchanged" do
    card = cards(:one)
    card.update!(title: "Point Row Card 72",
                 start_date: nil,
                 due_date: Time.utc(2026, 8, 4, 14, 0))
    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal 1, chip_count_for(card)
      assert_match(/2:00 PM/, response.body)
      assert_no_match(/Aug 4–/, response.body)
    end
  end

  test "panel: a same-day start and due renders as a point with the time, not a span" do
    card = cards(:one)
    card.update!(title: "Same Day Row Card 73",
                 start_date: Time.utc(2026, 8, 4, 9, 0),
                 due_date:   Time.utc(2026, 8, 4, 16, 0))
    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal 1, chip_count_for(card)
      assert_match(/4:00 PM/, response.body)
      assert_no_match(/Aug 4–4/, response.body)
    end
  end

  # The tempting mistake: labelling the span with the days that happen to be
  # visible. The window here is Aug 1..Aug 22 but the card really runs Jul 28 to
  # Aug 26, so a clipped label would read "Aug 1 – Aug 22" and misstate the card.
  test "panel: a range extending past both window edges shows its TRUE span" do
    card = cards(:one)
    card.update!(title: "True Span Card 74",
                 start_date: Time.utc(2026, 7, 28, 9, 0),
                 due_date:   Time.utc(2026, 8, 26, 17, 0))
    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_match(/Jul 28 – Aug 26/, response.body, "span must be the card's real range")
      assert_no_match(/Aug 1 – Aug 22/, response.body, "span must not be clipped to the visible window")
    end
  end

  test "panel: a cross-month span spells out both months" do
    card = cards(:one)
    card.update!(title: "Cross Month Card 75",
                 start_date: Time.utc(2026, 8, 30, 9, 0),
                 due_date:   Time.utc(2026, 9, 2, 17, 0))
    travel_to Time.utc(2026, 8, 29, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_match(/Aug 30 – Sep 2/, response.body)
    end
  end

  test "panel: a same-month span collapses the repeated month" do
    card = cards(:one)
    card.update!(title: "Same Month Card 76",
                 start_date: Time.utc(2026, 8, 10, 9, 0),
                 due_date:   Time.utc(2026, 8, 12, 17, 0))
    travel_to Time.utc(2026, 8, 9, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_match(/Aug 10–12/, response.body)
      assert_no_match(/Aug 10 – Aug 12/, response.body, "same month should not repeat the month name")
    end
  end

  # --- long ranges collapse to start / today / due ---
  #
  # Showing a range card on every spanned day meant one long card filled the whole
  # agenda (the window is today..today+21 = 22 days, so a quarter-long epic took
  # every row). It now appears on at most three days: its start, today, and its
  # due day — each only when that day is both inside the window AND inside the
  # span. Today is always inside the window (it's day one), so the "today" row
  # applies whenever today falls within the span.
  #
  # All times are explicit Time.utc: the app runs UTC and these assert on which
  # calendar day a row lands, which local-midnight arithmetic silently shifts.

  # A span already underway: 19 spanned days previously meant 19 agenda rows.
  #
  # Note it collapses to TWO rows, not three. The window begins today, so a start
  # day earlier than today is always outside it and clipped — and today can only
  # sit mid-span when start < today. Those two facts together cap a range card at
  # two agenda rows; "start + today + due" is only ever three distinct days if the
  # window reached into the past, which it doesn't.
  test "panel: a span already underway collapses to today and its due day" do
    card = cards(:one)
    card.update!(title: "Long Span 81",
                 start_date: Time.utc(2026, 8, 2, 9, 0),
                 due_date:   Time.utc(2026, 8, 20, 17, 0))

    travel_to Time.utc(2026, 8, 10, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 20)],
                   panel_days_for(card), "today and due; the Aug 2 start precedes the window"
      assert_equal 2, chip_count_for(card)
      assert_equal ["in_progress", "due"], panel_roles_for(card)
    end
  end

  test "panel: no range card ever exceeds two agenda rows" do
    card = cards(:one)
    # A full quarter — the worst case that motivated collapsing at all.
    card.update!(title: "Quarter Span 92",
                 start_date: Time.utc(2026, 6, 1, 9, 0),
                 due_date:   Time.utc(2026, 8, 20, 17, 0))

    travel_to Time.utc(2026, 8, 10, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_operator chip_count_for(card), :<=, 2, "was 22 rows before collapsing"
      assert_equal ["in_progress", "due"], panel_roles_for(card)
    end
  end

  test "panel: a month-long span whose ends fall outside the window shows only today" do
    card = cards(:one)
    card.update!(title: "Month Span 82",
                 start_date: Time.utc(2026, 7, 20, 9, 0),
                 due_date:   Time.utc(2026, 8, 30, 17, 0))

    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      # Start and due are both out of window, so only the in-progress row remains
      # — down from 22 rows, which is the whole point of collapsing.
      assert_equal [Date.new(2026, 8, 1)], panel_days_for(card)
      assert_equal ["in_progress"], panel_roles_for(card)
    end
  end

  # A short span starting today — the reachable analogue of "today mid-span", since
  # a start before today is always clipped by the window.
  test "panel: a three-day span starting today shows its start and due days" do
    card = cards(:one)
    card.update!(title: "Short Span 83",
                 start_date: Time.utc(2026, 8, 10, 9, 0),
                 due_date:   Time.utc(2026, 8, 12, 17, 0))

    travel_to Time.utc(2026, 8, 10, 8, 0) do
      get planner_panel_url

      assert_response :success
      # The middle day (Aug 11) is the one collapsing drops for a short span.
      assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 12)], panel_days_for(card)
      assert_equal ["starts", "due"], panel_roles_for(card)
    end
  end

  test "panel: a span starting before the window has no starts row" do
    card = cards(:one)
    card.update!(title: "Pre Window Span 84",
                 start_date: Time.utc(2026, 7, 25, 9, 0),
                 due_date:   Time.utc(2026, 8, 10, 17, 0))

    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal [Date.new(2026, 8, 1), Date.new(2026, 8, 10)], panel_days_for(card)
      assert_equal ["in_progress", "due"], panel_roles_for(card)
    end
  end

  test "panel: a span ending after the window has no due row" do
    card = cards(:one)
    card.update!(title: "Post Window Span 85",
                 start_date: Time.utc(2026, 8, 12, 9, 0),
                 due_date:   Time.utc(2026, 9, 30, 17, 0))

    travel_to Time.utc(2026, 8, 10, 8, 0) do
      get planner_panel_url

      assert_response :success
      # Due (Sep 30) is past the window edge and drops; only the start row is left.
      assert_equal [Date.new(2026, 8, 12)], panel_days_for(card)
      assert_equal ["starts"], panel_roles_for(card)
    end
  end

  test "panel: a span not containing today shows just start and due" do
    card = cards(:one)
    card.update!(title: "Future Span 86",
                 start_date: Time.utc(2026, 8, 5, 9, 0),
                 due_date:   Time.utc(2026, 8, 12, 17, 0))

    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal [Date.new(2026, 8, 5), Date.new(2026, 8, 12)], panel_days_for(card)
      assert_equal ["starts", "due"], panel_roles_for(card)
    end
  end

  test "panel: when today is the due day the row reads due, not in progress" do
    card = cards(:one)
    card.update!(title: "Today Is Due 87",
                 start_date: Time.utc(2026, 8, 5, 9, 0),
                 due_date:   Time.utc(2026, 8, 10, 17, 0))

    travel_to Time.utc(2026, 8, 10, 8, 0) do
      get planner_panel_url

      assert_response :success
      # due > starts > in_progress: today is inside the span AND is the due day, so
      # the row must read "due" rather than "in_progress". (The Aug 5 start is
      # before the window and drops, leaving exactly the row under test.)
      assert_equal [Date.new(2026, 8, 10)], panel_days_for(card)
      assert_equal ["due"], panel_roles_for(card)
    end
  end

  test "panel: when today is the start day the row reads starts, not in progress" do
    card = cards(:one)
    card.update!(title: "Today Is Start 88",
                 start_date: Time.utc(2026, 8, 10, 9, 0),
                 due_date:   Time.utc(2026, 8, 18, 17, 0))

    travel_to Time.utc(2026, 8, 10, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal [Date.new(2026, 8, 10), Date.new(2026, 8, 18)], panel_days_for(card)
      assert_equal ["starts", "due"], panel_roles_for(card)
    end
  end

  test "panel: a due-only card is one row with no role marker" do
    card = cards(:one)
    card.update!(title: "Due Only 89", start_date: nil, due_date: Time.utc(2026, 8, 5, 14, 0))

    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal [Date.new(2026, 8, 5)], panel_days_for(card)
      assert_empty panel_roles_for(card), "a point needs no explanation"
      assert_match(/2:00 PM/, response.body)
    end
  end

  test "panel: a same-day start and due is one point row with no role marker" do
    card = cards(:one)
    card.update!(title: "Same Day 90",
                 start_date: Time.utc(2026, 8, 5, 9, 0),
                 due_date:   Time.utc(2026, 8, 5, 16, 0))

    travel_to Time.utc(2026, 8, 1, 8, 0) do
      get planner_panel_url

      assert_response :success
      assert_equal [Date.new(2026, 8, 5)], panel_days_for(card)
      assert_empty panel_roles_for(card)
      assert_match(/4:00 PM/, response.body)
    end
  end

  # The easiest thing to break by accident: only the AGENDA collapses. The
  # calendar grid must still draw a bar segment on every single spanned day.
  test "grid regression: a spanning card still renders a segment on every spanned day" do
    card = cards(:one)
    card.update!(title: "Grid Bar Card 91",
                 start_date: Time.utc(2026, 5, 4, 9, 0),
                 due_date:   Time.utc(2026, 5, 12, 17, 0))

    get planner_url(year: 2026, month: 5)

    assert_response :success
    # May 4..12 inclusive = 9 days, every one of them a bar cell.
    assert_equal 9, chip_count_for(card), "the grid must not collapse — only the agenda does"
    assert_match(/data-planner-segment="start"/, response.body)
    assert_match(/data-planner-segment="middle"/, response.body)
    assert_match(/data-planner-segment="end"/, response.body)
  end

  # --- grid tidy-up: row-wrap seams (Item 2) ---
  #
  # May 4-12, 2026 crosses a week boundary at Saturday the 9th / Sunday the
  # 10th — the exact seam the brief flagged. A :middle segment landing on
  # Saturday (the grid's last column) or Sunday (the first column of the next
  # row) has no same-row neighbour to bleed its negative margin toward; before
  # this pass it bled anyway, off the edge of the grid. Now it caps with a
  # rounded corner instead, the same as a real :start/:end already did.

  test "a middle segment landing on the last column of a row caps its right edge instead of bleeding off the grid" do
    card = cards(:one)
    card.update!(title: "Grid Bar Card 91",
                 start_date: Time.utc(2026, 5, 4, 9, 0),
                 due_date:   Time.utc(2026, 5, 12, 17, 0))

    get planner_url(year: 2026, month: 5)

    cell = cell_html_for(Date.new(2026, 5, 9)) # Saturday — row-end, not the range's real end
    assert_match(/data-planner-segment="middle"/, cell)
    assert_match "rounded-r", cell
    assert_no_match(/(?<!-)mr-1\.5/, cell, "a row-end middle segment must not bleed past the grid's right edge")
  end

  test "a middle segment landing on the first column of a row caps its left edge instead of bleeding off the grid" do
    card = cards(:one)
    card.update!(title: "Grid Bar Card 91",
                 start_date: Time.utc(2026, 5, 4, 9, 0),
                 due_date:   Time.utc(2026, 5, 12, 17, 0))

    get planner_url(year: 2026, month: 5)

    cell = cell_html_for(Date.new(2026, 5, 10)) # Sunday — row-start, not the range's real start
    assert_match(/data-planner-segment="middle"/, cell)
    assert_match "rounded-l", cell
    assert_no_match(/(?<!-)ml-1\.5/, cell, "a row-start middle segment must not bleed past the grid's left edge")
  end

  test "a middle segment mid-row still bleeds into its neighbours, unlike the row edges above" do
    card = cards(:one)
    card.update!(title: "Grid Bar Card 91",
                 start_date: Time.utc(2026, 5, 4, 9, 0),
                 due_date:   Time.utc(2026, 5, 12, 17, 0))

    get planner_url(year: 2026, month: 5)

    cell = cell_html_for(Date.new(2026, 5, 6)) # Wednesday — an ordinary mid-row day
    assert_match(/data-planner-segment="middle"/, cell)
    assert_match "-ml-1.5", cell
    assert_match "-mr-1.5", cell
  end

  test "the day grid draws its lines once, not per cell" do
    get planner_url(year: 2026, month: 5)

    assert_response :success
    assert_no_match "border-r", response.body
    assert_no_match "last:border-r-0", response.body
  end

  # --- per-week lane assignment (Item 3) ---
  #
  # Each day cell used to stack its own chips independently — a spanning
  # card's vertical position depended on whatever ELSE fell on that
  # particular day, so a bar visibly stepped up and down across a week
  # instead of reading as one straight line. These pin
  # PlannerHelper#planner_week_lanes, which assigns every spanning card a
  # lane index that's stable for its whole week row, rendered via the
  # view's data-planner-lane attribute. August 9-22, 2026 is two full
  # Sunday-Saturday weeks, matching the exact seam the brief flagged.

  test "a range spanning a full week occupies the same lane index in every cell of that row" do
    board = @user.boards.create!(name: "Lane Test Board 1")
    list  = board.lists.create!(name: "L", position: 1)
    spanning = list.cards.create!(title: "Full Week Span", position: 1,
                                   start_date: Date.new(2026, 8, 9).noon,
                                   due_date:   Date.new(2026, 8, 15).noon)

    # Point chips scattered unevenly across the row — different counts on
    # different days — is exactly what used to displace the bar to a
    # different stack position from one cell to the next.
    { Date.new(2026, 8, 10) => 2, Date.new(2026, 8, 12) => 1, Date.new(2026, 8, 14) => 3 }.each do |date, count|
      count.times do |i|
        list.cards.create!(title: "Noise #{date.iso8601} #{i}", position: 2 + i, due_date: date.noon)
      end
    end

    get planner_url(year: 2026, month: 8)
    assert_response :success

    (Date.new(2026, 8, 9)..Date.new(2026, 8, 15)).each do |date|
      assert_equal 0, lane_for(spanning, date),
                   "expected #{spanning.title} to stay in lane 0 on #{date}, regardless of how many point " \
                   "chips share that day"
    end
  end

  test "a range that starts mid-week and another that starts later get different lanes and do not collide" do
    board = @user.boards.create!(name: "Lane Test Board 2")
    list  = board.lists.create!(name: "L", position: 1)
    mid_week = list.cards.create!(title: "Mid Week Start", position: 1,
                                   start_date: Date.new(2026, 8, 11).noon, # Tuesday
                                   due_date:   Date.new(2026, 8, 13).noon) # Thursday
    starts_later = list.cards.create!(title: "Starts Later", position: 2,
                                       start_date: Date.new(2026, 8, 12).noon, # Wednesday: overlaps mid_week
                                       due_date:   Date.new(2026, 8, 14).noon) # Friday

    get planner_url(year: 2026, month: 8)
    assert_response :success

    overlap_day = Date.new(2026, 8, 12)
    lane_a = lane_for(mid_week, overlap_day)
    lane_b = lane_for(starts_later, overlap_day)

    assert_not_nil lane_a, "expected #{mid_week.title} to have a lane on #{overlap_day}"
    assert_not_nil lane_b, "expected #{starts_later.title} to have a lane on #{overlap_day}"
    refute_equal lane_a, lane_b, "overlapping ranges must not share a lane"
  end

  test "point chips render below the spanning lanes" do
    board = @user.boards.create!(name: "Lane Test Board 3")
    list  = board.lists.create!(name: "L", position: 1)
    spanning = list.cards.create!(title: "Spanning Card", position: 1,
                                   start_date: Date.new(2026, 8, 9).noon,
                                   due_date:   Date.new(2026, 8, 11).noon)
    point = list.cards.create!(title: "Point Card", position: 2, due_date: Date.new(2026, 8, 10).noon)

    get planner_url(year: 2026, month: 8)
    assert_response :success

    cell = cell_html_for(Date.new(2026, 8, 10))
    spanning_index = cell.index(%(href="#{card_path(spanning)}"))
    point_index    = cell.index(%(href="#{card_path(point)}"))

    assert spanning_index, "expected the spanning card's chip in this cell"
    assert point_index, "expected the point card's chip in this cell"
    assert_operator spanning_index, :<, point_index,
                    "point chips must render below (after, in DOM order) the spanning lanes, so they can never " \
                    "displace a bar"
  end

  test "row-boundary caps still apply correctly when a card shares its row with another lane" do
    board = @user.boards.create!(name: "Lane Test Board 4")
    list  = board.lists.create!(name: "L", position: 1)
    # Crosses the Aug 15/16 week boundary, in lane 0.
    crossing = list.cards.create!(title: "Crossing Range", position: 1,
                                   start_date: Date.new(2026, 8, 9).noon,
                                   due_date:   Date.new(2026, 8, 22).noon)
    # Confined to the middle of the same row, so it packs into lane 1
    # alongside `crossing`'s lane 0 without ever overlapping it.
    list.cards.create!(title: "Short Range", position: 2,
                        start_date: Date.new(2026, 8, 12).noon,
                        due_date:   Date.new(2026, 8, 14).noon)

    get planner_url(year: 2026, month: 8)
    assert_response :success

    saturday = Date.new(2026, 8, 15) # this row's last column — a real seam, not the range's true end
    assert_equal 0, lane_for(crossing, saturday)

    cell = cell_html_for(saturday)
    href = %(href="#{card_path(crossing)}")
    idx  = cell.index(href)
    tag  = cell[cell.rindex("<a ", idx)..cell.index(">", idx)]
    assert_match(/data-planner-segment="middle"/, tag)
    assert_includes tag, "rounded-r", "the row-boundary cap must still apply with a second lane present"
  end

  test "lane assignment is stable across repeated renders of the same data" do
    board = @user.boards.create!(name: "Lane Test Board 5")
    list  = board.lists.create!(name: "L", position: 1)
    a = list.cards.create!(title: "Stable A", position: 1,
                            start_date: Date.new(2026, 8, 9).noon,  due_date: Date.new(2026, 8, 12).noon)
    b = list.cards.create!(title: "Stable B", position: 2,
                            start_date: Date.new(2026, 8, 10).noon, due_date: Date.new(2026, 8, 13).noon)
    c = list.cards.create!(title: "Stable C", position: 3,
                            start_date: Date.new(2026, 8, 12).noon, due_date: Date.new(2026, 8, 14).noon)
    overlap_day = Date.new(2026, 8, 12) # all three cards are active on this day

    get planner_url(year: 2026, month: 8)
    assert_response :success
    first_lanes = [a, b, c].map { |card| lane_for(card, overlap_day) }

    get planner_url(year: 2026, month: 8)
    assert_response :success
    second_lanes = [a, b, c].map { |card| lane_for(card, overlap_day) }

    assert first_lanes.all?, "expected every card to have a lane assigned"
    assert_equal first_lanes, second_lanes, "the same data must produce the same lanes on every render"
  end

  test "panel query count stays flat as the number of range cards grows" do
    small = count_queries_for_panel(range_cards: 3)
    large = count_queries_for_panel(range_cards: 6)

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

  # The single day cell's markup, keyed off its data-day attribute (mirrors
  # panel_days_for's use of the panel's own data-agenda-day marker) — lets a
  # test assert on classes within ONE cell instead of the whole grid, so
  # "no bleed here" doesn't accidentally pass just because some OTHER day's
  # cell still bleeds.
  def cell_html_for(date)
    marker = %(data-day="#{date.iso8601}")
    start = response.body.index(marker)
    assert start, "expected to find a day cell for #{date}"
    # Cells are flat siblings; the next data-day="..." (or the grid's own
    # closing tags, for the last cell) bounds this one.
    stop = response.body.index('data-day="', start + marker.length) || response.body.length
    response.body[start...stop]
  end

  # The lane index (data-planner-lane) a card's chip rendered in on one
  # specific day, scoped to that day's own cell so a same-titled/positioned
  # chip elsewhere in the grid can't be picked up by mistake. nil if the
  # card has no chip in that cell at all (e.g. a point chip, which carries
  # no lane attribute).
  def lane_for(card, date)
    cell = cell_html_for(date)
    href = %(href="#{card_path(card)}")
    idx = cell.index(href)
    return nil unless idx

    tag = cell[cell.rindex("<a ", idx)..cell.index(">", idx)]
    match = tag.match(/data-planner-lane="(\d+)"/)
    match && match[1].to_i
  end

  # Which agenda day-groups a card is rendered under, ascending. Keyed off the
  # group's data-agenda-day attribute rather than its human label, which is
  # "Today"/"Tomorrow" for the first two days and a formatted date after that.
  def panel_days_for(card)
    href = %(href="#{card_path(card)}")
    response.body
            .split(/<div class="mb-5" data-agenda-day="/)
            .drop(1)
            .filter_map do |chunk|
              day, rest = chunk.split('"', 2)
              Date.parse(day) if rest.to_s.include?(href)
            end
  end

  # Role markers ("starts" / "in_progress" / "due") for a card's agenda rows, in
  # document order. Keyed off the data-agenda-role attribute rather than the
  # visible text so the assertion doesn't depend on wording or markup.
  def panel_roles_for(card)
    href = %(href="#{card_path(card)}")
    response.body
            .split(/<div class="mb-5" data-agenda-day="/)
            .drop(1)
            .filter_map do |chunk|
              next unless chunk.include?(href)
              chunk[/data-agenda-role="([^"]*)"/, 1]
            end
            .reject { |r| r.to_s.empty? }
  end

  # The panel renders a chip per spanned day per card, so a missing preload
  # shows up as growth. Fresh user + sign-in per measurement: reusing one Warden
  # session across two requests adds a session-revalidation query unrelated to
  # card count.
  def count_queries_for_panel(range_cards:)
    user = User.create!(email: "panelperf#{range_cards}@example.com", password: "password")
    sign_in user

    board = user.boards.create!(name: "Panel Perf Board #{range_cards}")
    board.lists.destroy_all
    list = board.lists.create!(name: "List", position: 1)

    range_cards.times do |i|
      card = list.cards.create!(
        title: "Panel Range #{i}",
        start_date: (Date.current + 1.day).to_time.change(hour: 9),
        due_date:   (Date.current + 3.days).to_time.change(hour: 17)
      )
      # The chip reads card.labels.first and card.list.board.name — both are in
      # the action's includes, so both must stay flat as the card count grows.
      card.labels << board.labels.create!(name: "PL#{i}", color: "blue")
    end

    result = count_queries { get planner_panel_url }
    assert_response :success
    sign_out user
    result
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
