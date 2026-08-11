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
    verified_interaction("close the modal via the X", effect: -> { has_no_selector?("[data-modal-target='dialog']") }) do
      find("a[aria-label='Close card']").click
    end

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

    click_modal_backdrop

    assert_modal_closed
  end

  private

  # Click the dark backdrop, not the panel sitting on top of it.
  #
  # The backdrop is `absolute inset-0`, i.e. the whole viewport, so its CENTRE is
  # behind the modal panel — a plain .click is intercepted by whatever modal
  # control happens to sit there (Selenium says so explicitly rather than
  # silently clicking the wrong thing). The click therefore has to be OFFSET into
  # the gutter beside the panel.
  #
  # That offset used to be a hardcoded `x: -660`, and that is the part worth
  # fixing: an offset click is the one Selenium click that does NOT run the
  # obscured-element check, so if the viewport ever narrows or the panel ever
  # widens past that point, the click lands ON THE PANEL and the test fails with
  # "modal didn't close" — a lie about where the bug is. Derive the offset from
  # the live geometry instead, and assert the point really does hit the backdrop
  # before clicking, so a layout change fails with the actual reason.
  def click_modal_backdrop
    backdrop = find("a[data-modal-exit]", match: :first)

    offset_x, hits_backdrop, gutter = page.evaluate_script(<<~JS, backdrop)
      (() => {
        const el = arguments[0]
        const panel = document.querySelector('[data-modal-target="dialog"]')
        const r = el.getBoundingClientRect()
        const p = panel.getBoundingClientRect()

        // Midpoint of the gutter between the viewport's left edge and the panel.
        const x = Math.round(p.left / 2)
        const y = Math.round(r.top + r.height / 2)

        return [
          Math.round(x - (r.left + r.width / 2)), // Capybara offsets from the centre
          document.elementFromPoint(x, y) === el,
          Math.round(p.left)
        ]
      })()
    JS

    assert hits_backdrop,
      "the computed backdrop click point is not on the backdrop (gutter beside the " \
      "panel is #{gutter}px wide) — the modal panel may now span the full viewport, " \
      "in which case this test needs a different way to reach the backdrop"

    verified_interaction("click the modal backdrop", effect: -> { has_no_selector?("[data-modal-target='dialog']") }) do
      backdrop.click(x: offset_x, y: 0)
    end
  end

  def open_modal
    # Same shape as the click captured misfiring during the flake-root-cause
    # investigation (CardCreationTest's add-card trigger): an anchor inside a
    # turbo-frame-scoped element, opening via a frame navigation rather than a
    # page-level Drive visit.
    verified_interaction("open the card modal", effect: -> { has_selector?("[data-modal-target='dialog']") }) do
      find("#card_#{@card.id} a[data-turbo-frame='modal']", match: :first).click
    end

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
