require "application_system_test_case"

# Dragging a card between lists, and the move surviving a reload.
#
# CLAUDE.md records that drag persistence has been "silently broken" here before
# — the DOM moved, the PATCH didn't land or didn't stick, and nothing looked
# wrong until a reload. Nothing in the suite covered it, because the only way to
# catch it is to actually drag something in a browser.
#
# The pointer-event technique lives in ApplicationSystemTestCase#drag_card_to,
# with the full explanation of why the obvious approaches silently do nothing.
class CardDragTest < ApplicationSystemTestCase
  setup do
    @user  = users(:one)
    @board = boards(:one)

    # Fixtures give board one exactly one list with one card. Build the second
    # list here rather than extending the shared fixtures — several controller
    # tests assert on flat query counts and list/card totals, and adding rows to
    # fixtures they share would move those numbers for unrelated reasons.
    @source = lists(:one)
    @target = @board.lists.create!(name: "Target list", position: 2)

    @card = @source.cards.create!(title: "Draggable card", position: 2)
  end

  test "dragging a card to another list moves it and the move persists" do
    sign_in_as @user
    visit board_path(@board)

    assert_selector "#list_#{@source.id}_cards #card_#{@card.id}"

    # A drag isn't a click, so this isn't the click-race under investigation,
    # but CardDrag is one of the originally affected tests and the same
    # bounded-retry treatment applies: retry the WHOLE gesture (not a longer
    # wait) if SortableJS's optimistic DOM move never happens. drag_card_to
    # already drives real, trusted pointer events (Selenium's Actions API),
    # so retrying it doesn't introduce the JS-dispatched-click problem the
    # primitive is built to avoid.
    verified_interaction("drag the card to the target list", effect: -> { has_selector?("#list_#{@target.id}_cards #card_#{@card.id}") }, poll: 3) do
      drag_card_to @card, @target
    end

    assert_no_selector "#list_#{@source.id}_cards #card_#{@card.id}"

    # cards#move answers `head :ok` and re-renders nothing, so the record is the
    # only observable proof the move was actually persisted rather than just
    # moved on screen — which is the exact failure mode this test exists for.
    assert_eventually(message: "card was never persisted into the target list") do
      @card.reload.list_id == @target.id
    end

    # And the real assertion: a fresh page load from the server puts it there
    # too. Without this, a drag that updated the DB but rendered wrong (or vice
    # versa) still passes.
    visit board_path(@board)
    assert_selector "#list_#{@target.id}_cards #card_#{@card.id}"
    assert_no_selector "#list_#{@source.id}_cards #card_#{@card.id}"
  end

  # NOT COVERED, deliberately: dropping onto a list that ALREADY HAS CARDS.
  #
  # A second test doing exactly the above but with one card pre-existing in the
  # target failed on every run — and not by landing in the wrong position, but by
  # the drag never starting at all (no drag clone, card untouched, no
  # `cards:drag-start`). The app itself is fine: an ad-hoc probe of the same
  # scenario, driven by hand, moved the card and persisted it correctly. It is
  # driving it from the harness that is unreliable, and the first few pointer
  # moves are where it breaks.
  #
  # Left out rather than shipped flaky, per the rule that a flaky system test is
  # worse than none — it teaches people to ignore red. Worth another attempt, but
  # as its own piece of work, not by padding this one with waits until it goes
  # green.
end
