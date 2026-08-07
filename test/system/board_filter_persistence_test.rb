require "application_system_test_case"

# The board filter is pure client state (board_filter_controller.js toggling a
# `hidden` class) sitting on top of server-rendered card DOM. Nothing tested the
# seam between the two, which is the only place it can break.
#
# CABLE CAVEAT, and it shapes this whole file: adding a card does NOT make the
# card appear in a system test. cards#create broadcasts the new tile and its
# turbo_stream RESPONSE only resets the "Add a card" trigger — and broadcasts
# don't reach the browser here (see ApplicationSystemTestCase). What IS exercised
# is the real thing under test: a turbo_stream response landing on the page fires
# `turbo:before-stream-render`, which is the hook the filter re-applies on.
class BoardFilterPersistenceTest < ApplicationSystemTestCase
  setup do
    @board = boards(:one)
    @list  = lists(:one)
    @label = labels(:one)

    @labelled = @list.cards.create!(title: "Has the label")
    @labelled.labels << @label
    @plain = @list.cards.create!(title: "No label at all")

    sign_in_as users(:one)
    visit board_path(@board)
  end

  test "an applied filter survives a turbo_stream response" do
    filter_by_label

    # Sanity: the filter is actually doing something before we test that it
    # SURVIVES something. Capybara's text matching only sees visible text, and
    # the filter hides by class, so this is a real visibility assertion.
    assert_text "Has the label"
    assert_no_text "No label at all"

    add_a_card "Added while filtered"

    # The turbo_stream response has landed: the inline form is gone, replaced by
    # the trigger. This is the `turbo:before-stream-render` the filter hooks.
    assert_selector "#list_#{@list.id}_new_card", text: "Add a card"
    assert_no_selector "#list_#{@list.id}_new_card textarea"

    # The actual regression guard: a stream render must not blow away the filter.
    assert_text "Has the label"
    assert_no_text "No label at all"

    # ...and the URL still describes the same view, so a reload or a shared link
    # would reproduce it.
    assert_includes page.current_url, "filter_labels=#{@label.id}"

    # The card really was created — proof the action under test happened at all,
    # rather than the assertions above passing because nothing occurred. Its tile
    # is absent only because insertion is a broadcast.
    assert @list.cards.exists?(title: "Added while filtered")
  end

  # Different mechanism, also uncovered: on a full page load the filter is
  # re-derived from the URL (syncFromURL), not from surviving DOM state. This is
  # what makes a filtered board shareable — and it is the path that shows a
  # newly-added card being correctly hidden, which the turbo_stream test above
  # cannot see without cable.
  test "a filter applied in the URL is re-derived on a fresh page load" do
    filter_by_label
    add_a_card "Added while filtered"

    visit board_path(@board, filter_labels: @label.id)

    assert_text "Has the label"
    assert_no_text "No label at all"
    # A newly added, label-less card must be filtered out too.
    assert_no_text "Added while filtered"

    # The checkbox state is re-derived too, not just the card visibility — a
    # filtered board that shows no active filter is how you strand someone
    # wondering where their cards went.
    find("button[aria-label='Filter cards']").click
    assert find("input[data-category='label'][value='#{@label.id}']").checked?
  end

  private

  def filter_by_label
    find("button[aria-label='Filter cards']").click
    find("input[data-category='label'][value='#{@label.id}']").check

    # Close the popover so it can't intercept later clicks. Esc goes to
    # dropdown_controller's own element listener (focus is inside the popover).
    press_escape
    assert_no_selector "[data-dropdown-target='menu']", text: "Filter cards"
  end

  def add_a_card(title)
    find("#list_#{@list.id}_new_card a", text: "Add a card").click

    # The trigger frame swaps to the inline form.
    assert_selector "#list_#{@list.id}_new_card textarea"

    find("#list_#{@list.id}_new_card textarea").fill_in with: title
    find("#list_#{@list.id}_new_card input[type='submit']").click

    # cards#create's turbo_stream response renders no card (that's a broadcast),
    # so the record is the only proof the create actually completed.
    assert_eventually(message: "the card was never created") do
      @list.cards.exists?(title: title)
    end
  end
end
# The frame-destroying bug originally found by this file (cards/create using
# `replace` on the trigger's turbo-frame) is fixed — see
# cards/create.turbo_stream.erb — and pinned by CardCreationTest, which is where
# the two-cards-in-a-row case belongs.

