require "application_system_test_case"

# Esc closes an open dropdown and puts focus back on its trigger.
#
# This shipped recently with no regression test, and keyboard behaviour is
# exactly what a manual pass forgets to re-check — nobody tabs back to verify
# where focus went. dropdown_controller.js is explicit that returning focus is
# the point ("without that last part a keyboard user is dumped at the top of the
# document"), and that it deliberately does NOT move focus on click-outside. Both
# halves are asserted here.
#
# It also binds keydown on ITS OWN ELEMENT rather than the document, precisely so
# Esc inside a nested popover doesn't also close the card modal. That placement is
# what makes press_escape (which does not move focus) necessary — focusing <body>
# to send the key would skip this listener entirely and hit keyboard_controller's
# document-level chain instead.
class DropdownKeyboardTest < ApplicationSystemTestCase
  setup do
    @board = boards(:one)
    sign_in_as users(:one)
    visit board_path(@board)

    # The board-title dropdown: a plain trigger/menu pair with aria-expanded,
    # and no popover-specific behaviour layered on top.
    @trigger = find("button[data-dropdown-target='trigger']", text: @board.name)
  end

  test "Escape closes an open dropdown and returns focus to the trigger" do
    @trigger.click

    assert_selector "[data-dropdown-target='menu']", text: "Board menu"
    assert_equal "true", @trigger[:"aria-expanded"]

    press_escape

    assert_no_selector "[data-dropdown-target='menu']", text: "Board menu"
    assert_equal "false", @trigger[:"aria-expanded"]
    assert focused?(@trigger), "focus was not returned to the trigger"
  end

  test "clicking outside closes the dropdown without moving focus to the trigger" do
    @trigger.click
    assert_selector "[data-dropdown-target='menu']", text: "Board menu"

    # A deliberately inert target: the "Automation (coming soon)" placeholder is
    # a real focusable button outside the dropdown that navigates nowhere. Using
    # it means the click cannot accidentally open a card or follow a link, and
    # focus provably lands somewhere that is NOT the trigger.
    find("button[aria-label='Automation (coming soon)']").click

    assert_no_selector "[data-dropdown-target='menu']", text: "Board menu"
    assert_equal "false", @trigger[:"aria-expanded"]

    # The pointer already put focus where the user clicked — pulling it back to
    # the trigger here would be wrong, and the controller says so.
    refute focused?(@trigger), "click-outside should not move focus onto the trigger"
  end

  test "aria-expanded is not left stale after toggling closed" do
    @trigger.click
    assert_equal "true", @trigger[:"aria-expanded"]

    @trigger.click

    assert_no_selector "[data-dropdown-target='menu']", text: "Board menu"
    assert_equal "false", @trigger[:"aria-expanded"],
      "a closed menu reporting aria-expanded=true is worse than no attribute at all"
  end

  private

  def focused?(element)
    page.evaluate_script("document.activeElement === arguments[0]", element)
  end
end
