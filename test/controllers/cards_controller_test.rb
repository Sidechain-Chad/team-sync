require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board_one = boards(:one)
    @list_one = lists(:one)
    @list_two = lists(:two)
    # Same-board sibling of @list_one, for legitimate move-within-board tests.
    # (@list_two lives on boards(:two), which @user has no access to.)
    @list_three = @board_one.lists.create!(name: "List Three")
    @card = cards(:one)
    sign_in @user
  end

  test "should update card and log move activity when list changes" do
    assert_difference -> { Activity.count }, 1 do
      patch card_url(@card), params: { card: { list_id: @list_three.id } }
    end

    assert_redirected_to board_url(@list_three.board)
    @card.reload
    assert_equal @list_three.id, @card.list_id

    activity = Activity.last
    assert_equal "moved", activity.action
    assert_equal "#{@list_one.name} to #{@list_three.name}", activity.description
    assert_equal "moved this card from #{@list_one.name} to #{@list_three.name}", activity.message
  end

  test "should 404 when updating card list_id to a list on a board the user cannot access at all" do
    assert_no_difference -> { Activity.count } do
      patch card_url(@card), params: { card: { list_id: @list_two.id } }
    end

    assert_response :not_found
    assert_equal @list_one.id, @card.reload.list_id
  end

  test "should 422 when updating card list_id to a list on a different board the user owns" do
    other_board = @user.boards.create!(name: "Another Board")
    other_list = other_board.lists.create!(name: "Other List")

    assert_no_difference -> { Activity.count } do
      patch card_url(@card), params: { card: { list_id: other_list.id } }
    end

    assert_response :unprocessable_entity
    assert_equal @list_one.id, @card.reload.list_id
  end

  test "should update card and log general update activity when list does not change" do
    assert_difference -> { Activity.count }, 1 do
      patch card_url(@card), params: { card: { title: "Updated Title" } }
    end

    assert_redirected_to board_url(@board_one)
    @card.reload
    assert_equal "Updated Title", @card.title
    
    activity = Activity.last
    assert_equal "renamed", activity.action
  end

  test "should update card and log activity when attachments are added" do
    file = fixture_file_upload("test.png", "image/png")

    assert_difference -> { Activity.count }, 1 do
      patch card_url(@card), params: { card: { attachments: [file] } }, as: :turbo_stream
    end

    assert_response :success
    assert_match /turbo-stream action="replace" target="modal"/, response.body
    
    @card.reload
    assert_equal 1, @card.attachments.count

    activity = Activity.last
    assert_equal "added_attachment", activity.action
    assert_equal "test.png", activity.description
  end

  test "should not update card with invalid attachment type" do
    # Use an extension that is NOT in ALLOWED_EXTENSIONS
    file = fixture_file_upload("test.png", "application/x-ghostscript")
    file.instance_variable_set(:@original_filename, "test.exe")

    assert_no_difference -> { Activity.count } do
      patch card_url(@card), params: { card: { attachments: [file] } }, as: :turbo_stream
    end

    assert_response :success
    assert_match /turbo-stream action="replace" target="modal"/, response.body
    assert_match "isn't an allowed file type", flash[:alert]
  end

  test "should return no_content for empty location-only patch" do
    assert_no_difference -> { Activity.count } do
      patch card_url(@card), params: { card: {
        latitude: "", longitude: "", location_name: "", location_address: ""
      } }, as: :turbo_stream
    end

    assert_response :no_content
    @card.reload
    assert_nil @card.latitude
  end

  # Quick-remove × button on the card's location row — same param shape as
  # the blank-location patch above, but exercised against a card that
  # actually has a location set, so the clearing path (not the no-op guard)
  # is what's under test.
  test "quick-remove location button clears all four location fields" do
    @card.update!(latitude: 40.7128, longitude: -74.0060, location_name: "NYC", location_address: "New York, NY")

    patch card_url(@card), params: { card: {
      latitude: "", longitude: "", location_name: "", location_address: ""
    } }, as: :turbo_stream

    assert_response :success
    assert_match /turbo-stream action="replace" target="modal"/, response.body

    @card.reload
    assert_nil @card.latitude
    assert_nil @card.longitude
    assert @card.location_name.blank?
    assert @card.location_address.blank?
    assert_not @card.location?
  end

  # --- #move (drag-and-drop endpoint) ---
  # drag_controller.js PATCHes JSON with position/list_id nested under
  # "card", matching card_params' shape.

  test "move: cannot move card to a list on a board the user has no access to at all" do
    patch move_card_url(@card), params: { card: { list_id: @list_two.id, position: 1 } }, as: :json

    assert_response :not_found
    assert_equal @list_one.id, @card.reload.list_id
  end

  test "move: cannot move card to a list on a different board even one the user owns" do
    other_board = @user.boards.create!(name: "Another Board")
    other_list = other_board.lists.create!(name: "Other List")

    patch move_card_url(@card), params: { card: { list_id: other_list.id, position: 1 } }, as: :json

    assert_response :unprocessable_entity
    assert_equal @list_one.id, @card.reload.list_id
  end

  test "move: non-member cannot move a card belonging to another user's board" do
    sign_out @user
    sign_in users(:two)

    patch move_card_url(@card), params: { card: { list_id: @list_one.id, position: 1 } }, as: :json

    assert_response :not_found
  end

  test "move: board member can move a card between two lists on a shared board" do
    shared_board = @user.boards.create!(name: "Shared Board")
    list_a = shared_board.lists.create!(name: "List A")
    list_b = shared_board.lists.create!(name: "List B")
    card = list_a.cards.create!(title: "Shared Card")

    member = users(:two)
    shared_board.board_users.create!(user: member)
    sign_out @user
    sign_in member

    patch move_card_url(card), params: { card: { list_id: list_b.id, position: 1 } }, as: :json

    assert_response :success
    assert_equal list_b.id, card.reload.list_id
  end

  test "move: moving to top of same list sets position 1 and shifts others down" do
    list = @board_one.lists.create!(name: "Position List")
    c1 = list.cards.create!(title: "C1")
    c2 = list.cards.create!(title: "C2")
    c3 = list.cards.create!(title: "C3")

    patch move_card_url(c3), params: { card: { list_id: list.id, position: 1 } }, as: :json

    assert_response :success
    assert_equal 1, c3.reload.position
    assert_equal 2, c1.reload.position
    assert_equal 3, c2.reload.position
  end

  test "move: moving to bottom of same list sets position to card count" do
    list = @board_one.lists.create!(name: "Position List 2")
    c1 = list.cards.create!(title: "C1")
    c2 = list.cards.create!(title: "C2")
    c3 = list.cards.create!(title: "C3")

    patch move_card_url(c1), params: { card: { list_id: list.id, position: 3 } }, as: :json

    assert_response :success
    assert_equal 3, c1.reload.position
    assert_equal 1, c2.reload.position
    assert_equal 2, c3.reload.position
  end

  test "move: moving into a different list closes the gap in the source list and inserts correctly in target" do
    source = @board_one.lists.create!(name: "Source")
    target = @board_one.lists.create!(name: "Target")
    s1 = source.cards.create!(title: "S1")
    s2 = source.cards.create!(title: "S2")
    s3 = source.cards.create!(title: "S3")
    t1 = target.cards.create!(title: "T1")
    t2 = target.cards.create!(title: "T2")

    patch move_card_url(s2), params: { card: { list_id: target.id, position: 2 } }, as: :json

    assert_response :success
    s2.reload
    assert_equal target.id, s2.list_id
    assert_equal 2, s2.position

    assert_equal 1, t1.reload.position
    assert_equal 3, t2.reload.position

    assert_equal 1, s1.reload.position
    assert_equal 2, s3.reload.position
  end

  # --- "Move to list" menu (card modal, Actions section) ---
  # Submits to #update (not #move) with a semantic top/bottom position
  # rather than a raw number — the controller resolves it against the
  # actual target list.

  test "member moves a card to another list at top via the move-to-list menu and logs activity" do
    existing_in_target = @list_three.cards.create!(title: "Already in Three")

    assert_difference -> { Activity.count }, 1 do
      patch card_url(@card), params: { card: { list_id: @list_three.id, position: "top" } }
    end

    assert_redirected_to board_url(@list_three.board)
    @card.reload
    assert_equal @list_three.id, @card.list_id
    assert_equal 1, @card.position
    assert_equal 2, existing_in_target.reload.position

    activity = Activity.last
    assert_equal "moved", activity.action
    assert_equal "#{@list_one.name} to #{@list_three.name}", activity.description
  end

  test "member moves a card to another list at bottom via the move-to-list menu" do
    existing_in_target = @list_three.cards.create!(title: "Already in Three")

    patch card_url(@card), params: { card: { list_id: @list_three.id, position: "bottom" } }

    assert_redirected_to board_url(@list_three.board)
    @card.reload
    assert_equal @list_three.id, @card.list_id
    assert_equal 2, @card.position
    assert_equal 1, existing_in_target.reload.position
  end

  test "member moves a card to bottom within its own current list via the move-to-list menu" do
    list = @board_one.lists.create!(name: "Same List Position Test")
    c1 = list.cards.create!(title: "C1")
    c2 = list.cards.create!(title: "C2")
    c3 = list.cards.create!(title: "C3")

    # c1 is already in `list` — moving it to "bottom" of the SAME list it's
    # already in must land it at the true bottom (position 3), not one past
    # it (4), which is what target_list.cards.count + 1 would naively give
    # since that count still includes c1 itself.
    patch card_url(c1), params: { card: { list_id: list.id, position: "bottom" } }

    assert_response :redirect
    assert_equal 3, c1.reload.position
    assert_equal 1, c2.reload.position
    assert_equal 2, c3.reload.position
  end

  test "move-to-list select only offers lists from the card's own board" do
    foreign_board = @user.boards.create!(name: "Another Accessible Board")
    foreign_board.lists.create!(name: "Should Not Appear List")

    get card_url(@card)

    assert_response :success
    assert_no_match(/Should Not Appear List/, response.body)
    assert_match(/#{Regexp.escape(@list_three.name)}/, response.body)
  end

  # Trello parity pass reverses the earlier cleanup: the sidebar "Move to
  # list" form is gone, and the header chip is the move control again (now
  # with a numeric Position select instead of the old top/bottom-only form).
  test "the modal has exactly one list_id select, and the header list name is a button that opens the move popover" do
    get card_url(@card)

    assert_response :success
    assert_select "select[name='card[list_id]']", count: 1
    assert_select "button[aria-label=?]", "Move card, currently in #{@list_one.name}", count: 1
  end

  # --- Phase A: Trello-anatomy modal restructure ---
  # Relocation, not rebuild: the assertions below check WHERE things live.
  # Every behavior test above/below (checklist create, attachment upload,
  # location clear, move popover) exercises the same endpoints unchanged.

  test "modal title row has the complete-toggle button beside the title" do
    get card_url(@card)

    assert_response :success
    assert_not @card.completed?
    assert_select "button[aria-label=?]", "Mark complete", count: 1
    assert_select "button[aria-label=?]", "Mark incomplete", count: 0
  end

  test "modal title row shows the incomplete-toggle affordance when the card is already completed" do
    @card.update!(completed: true)

    get card_url(@card)

    assert_response :success
    assert_select "button[aria-label=?]", "Mark incomplete", count: 1
    assert_select "button[aria-label=?]", "Mark complete", count: 0
  end

  test "modal has exactly one archive control, inside the header's card-actions menu" do
    get card_url(@card)

    assert_response :success
    assert_select "#card_actions_menu form[action=?]", archive_card_path(@card), count: 1
    assert_select "form[action=?]", archive_card_path(@card), count: 1
    assert_select "button[aria-label=?]", "Card actions", count: 1
  end

  test "modal quick-add row (Checklist, Location, Attachment) lives in the left column" do
    get card_url(@card)

    assert_response :success
    assert_select "#quick_add_row button", count: 3
    assert_select "#quick_add_row i.fa-square-check", count: 1
    assert_select "#quick_add_row i.fa-location-dot", count: 1
    assert_select "#quick_add_row i.fa-paperclip", count: 1
  end

  test "right column is the comments-and-activity conversation pane only" do
    get card_url(@card)

    assert_response :success
    assert_select "#conversation_column h3", text: "Comments and activity", count: 1
    assert_select "#conversation_column #quick_add_row", count: 0
    assert_select "#conversation_column form[action=?]", archive_card_path(@card), count: 0
  end

  test "toggling complete from the modal updates card.completed and refreshes the modal" do
    assert_not @card.completed?

    patch toggle_complete_card_url(@card), params: { from_modal: true }, as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="replace" target="modal"/, response.body)
    assert_match "Mark incomplete", response.body
    assert @card.reload.completed?
  end

  test "toggling complete from the board tile (no from_modal) does not try to render the modal" do
    assert_not @card.completed?

    patch toggle_complete_card_url(@card), as: :turbo_stream

    assert_response :no_content
    assert @card.reload.completed?
  end

  test "move popover: integer position lands the card at that exact slot" do
    existing_in_target = @list_three.cards.create!(title: "Already in Three")
    existing_in_target2 = @list_three.cards.create!(title: "Already in Three 2")
    existing_in_target3 = @list_three.cards.create!(title: "Already in Three 3")

    patch card_url(@card), params: { card: { list_id: @list_three.id, position: 2 } }

    assert_redirected_to board_url(@list_three.board)
    @card.reload
    assert_equal @list_three.id, @card.list_id
    assert_equal 2, @card.position
  end

  test "move popover: out-of-range position clamps to the list's bounds" do
    @list_three.cards.create!(title: "Already in Three")

    patch card_url(@card), params: { card: { list_id: @list_three.id, position: 999 } }

    assert_redirected_to board_url(@list_three.board)
    @card.reload
    assert_equal @list_three.id, @card.list_id
    assert_equal 2, @card.position # bottom: 1 existing card + the moved card

    other_card = @list_three.cards.create!(title: "Bottom filler")
    patch card_url(other_card), params: { card: { list_id: @list_one.id, position: -5 } }

    assert_redirected_to board_url(@list_one.board)
    assert_equal 1, other_card.reload.position
  end

  # --- #move (drag) now logs a "moved" activity too, matching #update ---

  test "move: logs a moved activity when the list actually changes" do
    assert_difference -> { Activity.count }, 1 do
      patch move_card_url(@card), params: { card: { list_id: @list_three.id, position: 1 } }, as: :json
    end

    assert_response :success
    activity = Activity.last
    assert_equal "moved", activity.action
    assert_equal "#{@list_one.name} to #{@list_three.name}", activity.description
  end

  test "move: does not log a moved activity when staying in the same list" do
    assert_no_difference -> { Activity.count } do
      patch move_card_url(@card), params: { card: { list_id: @list_one.id, position: 1 } }, as: :json
    end

    assert_response :success
  end
end
