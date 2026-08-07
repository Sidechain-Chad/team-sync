require "application_system_test_case"

# Closing the card modal, both ways.
#
# CLAUDE.md records this frame-targeting area regressing three separate times —
# a missing `target: "_top"` or a dropped modal controller leaves the next close
# rendering "Content missing", and cards/show.html.erb carries a comment warning
# that its frame attributes must mirror the layout's. None of that was covered.
#
# Closing is a real navigation, not just emptying a frame: both the ✕ and the
# backdrop are links to the board (data-modal-exit, turbo_action: advance) on a
# frame declared target: "_top". So "closed" means: back on the board URL, with
# the modal frame present but empty.
class CardModalCloseTest < ApplicationSystemTestCase
  setup do
    @user  = users(:one)
    @board = boards(:one)
    @card  = lists(:one).cards.create!(title: "Card to open")

    sign_in_as @user
    visit board_path(@board)
  end

  test "closing the modal with the X returns to the board" do
    open_modal

    # aria-label rather than the glyph — the ✕ is a Font Awesome <i>, which has
    # no text for Capybara to match on.
    find("a[aria-label='Close card']").click

    assert_modal_closed
  end

  test "closing the modal with Escape returns to the board" do
    open_modal

    # Esc is handled by keyboard_controller's document-level chain, which clicks
    # the modal's own [data-modal-exit] link — so this exercises the same exit
    # path as the ✕, reached by keyboard. press_escape (not send_keys) so focus
    # is not moved on the way in; the modal has focus on its dialog already.
    press_escape

    assert_modal_closed
  end

  test "clicking the backdrop returns to the board" do
    open_modal

    # The backdrop is `absolute inset-0`, i.e. the whole viewport — so its CENTRE
    # is behind the modal panel, and a plain .click is intercepted by whatever
    # modal control happens to sit there (Selenium says so explicitly rather than
    # silently clicking the wrong thing). Offset well to the left, into the gutter
    # beside the panel, which is real backdrop.
    find("a[data-modal-exit]", match: :first).click(x: -660, y: 0)

    assert_modal_closed
  end

  private

  def open_modal
    find("#card_#{@card.id} a[data-turbo-frame='modal']", match: :first).click

    assert_selector "[data-modal-target='dialog']"
    assert_selector "[role='dialog'][aria-modal='true']"
  end

  def assert_modal_closed
    # The frame stays in the layout permanently; what must go is its contents.
    # `visible: :all` is required, not laziness: an EMPTY turbo-frame has no box,
    # so Capybara's default visibility filter rejects it — which is precisely the
    # state being asserted here.
    assert_no_selector "[data-modal-target='dialog']"
    assert_selector "turbo-frame#modal", visible: :all
    assert_empty find("turbo-frame#modal", visible: :all).text.strip
    assert_current_path board_path(@board)

    # And the board is genuinely usable again, rather than a blank frame or a
    # "Content missing" stub — which is exactly how the past regressions looked.
    assert_selector "#board_lists"
    assert_selector "#card_#{@card.id}"
  end
end
