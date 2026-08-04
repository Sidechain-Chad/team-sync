require "application_system_test_case"

# Adding two cards in a row.
#
# One card always worked; the SECOND one destroyed the board. cards/create's
# turbo_stream response used `replace` on `list_<id>_new_card`, which is a
# turbo-frame, so the frame was swapped out for a bare <a>. The next "Add a card"
# click was then unscoped and did a full Turbo Drive visit to
# /lists/:id/cards/new — a template consisting only of a turbo_frame_tag — so the
# board was replaced by a lone add-card form.
#
# Found by a system test; pinned by one. The second create is the whole point:
# a test that adds a single card passes against the broken code.
#
# CABLE CAVEAT: the created tiles arrive by broadcast and broadcasts don't reach
# the browser here, so this asserts the TRIGGER and the BOARD survive, plus the
# records — never that a card appears. See ApplicationSystemTestCase.
class CardCreationTest < ApplicationSystemTestCase
  setup do
    @board = boards(:one)
    @list  = lists(:one)

    sign_in_as users(:one)
    visit board_path(@board)
  end

  test "adding two cards in a row leaves the board and the trigger frame intact" do
    assert_trigger_is_a_frame

    add_a_card "First added card"

    # The frame must still be a frame here — this is the assertion the old code
    # failed, and everything below only works because of it.
    assert_trigger_is_a_frame
    assert_board_intact

    add_a_card "Second added card"

    assert_trigger_is_a_frame
    assert_board_intact

    # Both really were created: the assertions above must not be passing because
    # the clicks quietly did nothing.
    assert @list.cards.exists?(title: "First added card")
    assert @list.cards.exists?(title: "Second added card")
  end

  private

  def assert_trigger_is_a_frame
    # `visible: :all` is not laziness — see card_modal_close_test for the same
    # note. Here the frame does have visible content, but keeping the selector
    # tolerant means a failure reads as "not a frame" rather than "not visible".
    assert_selector "turbo-frame#list_#{@list.id}_new_card", visible: :all
    assert_selector "turbo-frame#list_#{@list.id}_new_card a", text: "Add a card"
  end

  def assert_board_intact
    assert_selector "#board_lists"
    assert_selector "#list_#{@list.id}_cards"
    assert_current_path board_path(@board)
  end

  def add_a_card(title)
    find("#list_#{@list.id}_new_card a", text: "Add a card").click
    assert_selector "#list_#{@list.id}_new_card textarea"

    find("#list_#{@list.id}_new_card textarea").fill_in with: title
    find("#list_#{@list.id}_new_card input[type='submit']").click

    # The create renders no card (broadcast), so the record is the only signal
    # that the round trip finished before we click again.
    assert_eventually(message: "the card was never created") do
      @list.cards.exists?(title: title)
    end
  end
end
