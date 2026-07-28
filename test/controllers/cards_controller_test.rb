require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

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

    # Notification.deliver's after_create_commit broadcasts via a Turbo
    # Streams job — see NotificationTest for why this needs the :test
    # adapter under transactional fixtures + the app's default :async adapter.
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  # --- #create ---

  test "create: no position appends to the bottom of the list" do
    @list_three.cards.create!(title: "Existing")

    assert_difference -> { Card.count }, 1 do
      post list_cards_url(@list_three), params: { card: { title: "New Card" } }, as: :turbo_stream
    end

    assert_response :success
    card = Card.find_by!(title: "New Card")
    assert_equal 2, card.position
  end

  test "create: an explicit position inserts the card there and shifts the rest down" do
    c1 = @list_three.cards.create!(title: "C1")
    c2 = @list_three.cards.create!(title: "C2")
    c3 = @list_three.cards.create!(title: "C3")
    c4 = @list_three.cards.create!(title: "C4")

    post list_cards_url(@list_three), params: { card: { title: "Inserted", position: 2 } }, as: :turbo_stream

    assert_response :success
    inserted = Card.find_by!(title: "Inserted")
    assert_equal 2, inserted.position
    assert_equal 1, c1.reload.position
    assert_equal 3, c2.reload.position
    assert_equal 4, c3.reload.position
    assert_equal 5, c4.reload.position
  end

  test "create: an out-of-range position clamps to the bottom of the list" do
    @list_three.cards.create!(title: "C1")
    @list_three.cards.create!(title: "C2")

    post list_cards_url(@list_three), params: { card: { title: "Inserted", position: 999 } }, as: :turbo_stream

    assert_response :success
    assert_equal 3, Card.find_by!(title: "Inserted").position
  end

  test "create: 404 for a list on a board the user cannot access at all" do
    assert_no_difference -> { Card.count } do
      post list_cards_url(@list_two), params: { card: { title: "Nope" } }
    end

    assert_response :not_found
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

  test "attach response replaces the modal frame WITH target=_top so the next close still breaks out" do
    file = fixture_file_upload("test.png", "image/png")

    patch card_url(@card), params: { card: { attachments: [file] } }, as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", response.body

    modal_frame_tag = response.body[/<turbo-frame[^>]*id="modal"[^>]*>/]
    assert modal_frame_tag, "expected a <turbo-frame id=\"modal\"> tag in the response"
    # The regression guard: the replaced modal frame must retain target="_top"...
    assert_match 'target="_top"', modal_frame_tag
    # ...and the self-close controller must survive the replace too.
    assert_match 'data-controller="modal"', modal_frame_tag
    assert_match "turbo:before-render@document-&gt;modal#close", modal_frame_tag
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

  test "modal close button defaults to the card's board with no return_to param" do
    get card_url(@card)

    assert_response :success
    assert_select "a[aria-label=?][href=?]", "Close card", board_path(@card.list.board)
  end

  test "modal close button returns to account cards, sort preserved, when opened with return_to=account" do
    get card_url(@card, return_to: "account", sort: "updated")

    assert_response :success
    assert_select "a[aria-label=?][href=?]", "Close card", account_cards_path(sort: "updated")
  end

  test "modal close button defaults sort to due for an unrecognized sort value" do
    get card_url(@card, return_to: "account", sort: "totally-not-a-real-sort")

    assert_response :success
    assert_select "a[aria-label=?][href=?]", "Close card", account_cards_path(sort: "due")
  end

  test "return_to is a strict whitelist — any value other than the literal 'account' falls back to the board" do
    get card_url(@card, return_to: "https://evil.example.com/phish")

    assert_response :success
    assert_select "a[aria-label=?][href=?]", "Close card", board_path(@card.list.board)
  end

  test "toggling complete from the modal opened over account cards preserves return_to across the re-render" do
    get card_url(@card, return_to: "account", sort: "updated")
    assert_response :success

    patch toggle_complete_card_url(@card),
      params: { from_modal: true, return_to: "account", sort: "updated" },
      as: :turbo_stream

    assert_response :success
    assert_select "a[aria-label=?][href=?]", "Close card", account_cards_path(sort: "updated")
  end

  test "a plain GET of a completed card's modal never carries the one-shot completion pop" do
    @card.update!(completed: true)

    get card_url(@card)

    assert_response :success
    assert_no_match(/animate-complete-pop/, response.body)
  end

  test "toggling complete from the modal updates card.completed and refreshes the modal" do
    assert_not @card.completed?

    patch toggle_complete_card_url(@card), params: { from_modal: true }, as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="replace" target="modal"/, response.body)
    assert_match "Mark incomplete", response.body
    assert_match "animate-complete-pop", response.body
    assert @card.reload.completed?
  end

  test "un-completing from the modal never carries the pop animation" do
    @card.update!(completed: true)

    patch toggle_complete_card_url(@card), params: { from_modal: true }, as: :turbo_stream

    assert_response :success
    assert_no_match(/animate-complete-pop/, response.body)
    assert_not @card.reload.completed?
  end

  test "toggling complete from the board tile (no from_modal) does not try to render the modal" do
    assert_not @card.completed?

    patch toggle_complete_card_url(@card), as: :turbo_stream

    assert_response :no_content
    assert @card.reload.completed?
  end

  test "toggling complete from the modal also broadcasts the row update to the member's own cards stream" do
    # This is the real-time-sync scenario: the modal is open (e.g. over
    # /account/cards), so the modal's own response only refreshes the
    # "modal" frame — the account row behind it can only update via this
    # per-member broadcast, not the response.
    assert_not @card.completed?
    row_id = ActionView::RecordIdentifier.dom_id(@card, :account_row)
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, [@user, :cards])

    broadcasts = capture_broadcasts(stream_name) do
      patch toggle_complete_card_url(@card), params: { from_modal: true }, as: :turbo_stream
    end

    assert_equal 1, broadcasts.size
    assert_match(/turbo-stream action="replace" target="#{row_id}"/, broadcasts.first)
    assert_match "animate-complete-pop", broadcasts.first
  end

  test "toggling complete from the board tile also broadcasts to the member's own cards stream" do
    assert_not @card.completed?
    row_id = ActionView::RecordIdentifier.dom_id(@card, :account_row)
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, [@user, :cards])

    broadcasts = capture_broadcasts(stream_name) do
      patch toggle_complete_card_url(@card), as: :turbo_stream
    end

    assert_equal 1, broadcasts.size
    assert_match(/turbo-stream action="replace" target="#{row_id}"/, broadcasts.first)
  end

  test "toggling complete from the account page returns an empty response and marks it just-completed via broadcast" do
    assert_not @card.completed?
    row_id = ActionView::RecordIdentifier.dom_id(@card, :account_row)

    stream_name = Turbo::StreamsChannel.send(:stream_name_from, [@user, :cards])
    broadcasts = capture_broadcasts(stream_name) do
      patch toggle_complete_card_url(@card), params: { from_account: true, sort: "due" }, as: :turbo_stream
    end

    # The response itself renders nothing now — the per-member broadcast
    # above is the only thing that updates the row, otherwise the actor
    # (who is one of @card.members, i.e. subscribed to that same stream)
    # would get the row replaced twice and the pop would double-play.
    assert_response :success
    assert_empty response.body
    assert_equal 1, broadcasts.size
    assert_match(/turbo-stream action="replace" target="#{row_id}"/, broadcasts.first)
    assert_match "Mark incomplete", broadcasts.first
    assert_match "animate-complete-pop", broadcasts.first
    assert @card.reload.completed?
  end

  test "un-completing from the account page never carries the pop animation, even in the broadcast" do
    @card.update!(completed: true)
    row_id = ActionView::RecordIdentifier.dom_id(@card, :account_row)

    stream_name = Turbo::StreamsChannel.send(:stream_name_from, [@user, :cards])
    broadcasts = capture_broadcasts(stream_name) do
      patch toggle_complete_card_url(@card), params: { from_account: true, sort: "due" }, as: :turbo_stream
    end

    assert_response :success
    assert_empty response.body
    assert_equal 1, broadcasts.size
    assert_match(/turbo-stream action="replace" target="#{row_id}"/, broadcasts.first)
    assert_no_match(/animate-complete-pop/, broadcasts.first)
    assert_not @card.reload.completed?
  end

  test "account page toggle HTML fallback redirects back to account cards, preserving sort" do
    assert_not @card.completed?

    patch toggle_complete_card_url(@card), params: { from_account: true, sort: "updated" }

    assert_redirected_to account_cards_url(sort: "updated")
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

  # --- #copy ---

  test "copy: creates exactly one new card and redirects to it" do
    assert_difference -> { Card.count }, 1 do
      post copy_card_url(@card), params: { list_id: @list_three.id, title: "Copied Card" }
    end

    new_card = Card.find_by!(title: "Copied Card")
    assert_redirected_to card_url(new_card)
  end

  test "copy: a card with members creates zero notifications (anti-spam guard)" do
    member = users(:two)
    @board_one.board_users.create!(user: member)
    @card.members << member

    assert_no_difference "Notification.count" do
      post copy_card_url(@card), params: { list_id: @list_three.id, title: "Copied" }
    end
  end

  test "copy: 404 for a target list on a board the user has no access to at all" do
    assert_no_difference -> { Card.count } do
      post copy_card_url(@card), params: { list_id: @list_two.id, title: "Nope" }
    end

    assert_response :not_found
  end

  test "copy: 422 for a target list on a different board the user owns" do
    other_board = @user.boards.create!(name: "Another Board")
    other_list = other_board.lists.create!(name: "Other List")

    assert_no_difference -> { Card.count } do
      post copy_card_url(@card), params: { list_id: other_list.id, title: "Nope" }
    end

    assert_response :unprocessable_entity
  end

  # --- #copy polish: turbo_stream response (keeps the board behind the modal) ---

  test "copy: turbo_stream response replaces the modal with the new card" do
    post copy_card_url(@card), params: { list_id: @list_three.id, title: "Copied Card" }, as: :turbo_stream

    assert_response :success
    new_card = Card.find_by!(title: "Copied Card")

    modal_frame_tag = response.body[/<turbo-frame[^>]*id="modal"[^>]*>/]
    assert modal_frame_tag, "expected a <turbo-frame id=\"modal\"> tag in the response"
    # Same regression guard as the attach response: the replaced modal frame
    # must retain target="_top" and the self-close controller, or the next
    # Esc/close breaks ("Content missing").
    assert_match 'target="_top"', modal_frame_tag
    assert_match 'data-controller="modal"', modal_frame_tag
    assert_match "turbo:before-render@document-&gt;modal#close", modal_frame_tag
    assert_match new_card.title, response.body
  end

  test "copy: html fallback still redirects to the new card" do
    assert_difference -> { Card.count }, 1 do
      post copy_card_url(@card), params: { list_id: @list_three.id, title: "Copied Card HTML" }
    end

    new_card = Card.find_by!(title: "Copied Card HTML")
    assert_redirected_to card_url(new_card)
  end

  # --- #copy polish: nested under the ⋯ menu, not a separate floating panel ---

  test "copy form lives nested inside the card-actions (···) menu popover" do
    get card_url(@card)

    assert_response :success
    assert_select "#card_actions_menu form[action=?]", copy_card_path(@card), count: 1
    assert_select "#card_actions_menu select[name='list_id']", count: 1
  end

  test "there is no separate floating Copy popover outside the card-actions menu" do
    get card_url(@card)

    assert_response :success
    assert_select "form[action=?]", copy_card_path(@card), count: 1
  end

  # --- #copy polish: graceful failure instead of a raw 500 ---

  test "copy: a copy_to failure redirects back to the source card with a flash error instead of a 500" do
    @card.update_column(:title, "")

    assert_no_difference -> { Card.count } do
      post copy_card_url(@card), params: { list_id: @list_three.id, title: "" }
    end

    assert_redirected_to card_url(@card)
    assert flash[:alert].present?
  end

  # --- broadcast-card-create: create/copy insert live for every board viewer ---

  test "create broadcasts the new card insert plus the list's card-count pill" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      post list_cards_url(@list_three), params: { card: { title: "Broadcast Card" } }, as: :turbo_stream
    end

    assert_response :success
    new_card = Card.find_by!(title: "Broadcast Card")
    # Asserted by target, not by count: a bare count can't tell a correct
    # second broadcast from a duplicate of the first.
    assert_equal [
      ["before",  "list_#{@list_three.id}_new_card"],
      ["replace", "list_#{@list_three.id}_card_count"]
    ].sort, broadcast_targets(broadcasts).sort

    insert = broadcast_for(broadcasts, "list_#{@list_three.id}_new_card")
    assert_match "id=\"#{ActionView::RecordIdentifier.dom_id(new_card)}\"", insert
    assert_match "Broadcast Card", insert
  end

  test "create response resets the trigger but does not itself render the new card (anti double-render)" do
    post list_cards_url(@list_three), params: { card: { title: "No Dup Card" } }, as: :turbo_stream

    assert_response :success
    new_card = Card.find_by!(title: "No Dup Card")
    assert_no_match(/id="#{ActionView::RecordIdentifier.dom_id(new_card)}"/, response.body)
    assert_match "list_#{@list_three.id}_new_card", response.body
    assert_match "Add a card", response.body
  end

  test "copy broadcasts the new card insert plus the target list's card-count pill" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      post copy_card_url(@card), params: { list_id: @list_three.id, title: "Broadcast Copy" }, as: :turbo_stream
    end

    assert_response :success
    new_card = Card.find_by!(title: "Broadcast Copy")
    assert_equal [
      ["before",  "list_#{@list_three.id}_new_card"],
      ["replace", "list_#{@list_three.id}_card_count"]
    ].sort, broadcast_targets(broadcasts).sort

    assert_match "id=\"#{ActionView::RecordIdentifier.dom_id(new_card)}\"",
                 broadcast_for(broadcasts, "list_#{@list_three.id}_new_card")
  end

  test "copy response contains the modal replace but not a second insertion of the new card" do
    post copy_card_url(@card), params: { list_id: @list_three.id, title: "Copy No Dup" }, as: :turbo_stream

    assert_response :success
    new_card = Card.find_by!(title: "Copy No Dup")
    assert_match(/turbo-stream action="replace" target="modal"/, response.body)
    assert response.body[/<turbo-frame[^>]*id="modal"[^>]*>/], "expected a <turbo-frame id=\"modal\"> tag in the response"
    # The mini board-card partial (cards/_card, wrapped in turbo_frame_tag
    # card => id="card_#{id}") is never rendered by the modal template —
    # its presence here would mean the response is STILL inserting the
    # card itself, duplicating the broadcast.
    assert_no_match(/turbo-stream action="before" target="list_#{@list_three.id}_new_card"/, response.body)
    assert_no_match(/id="#{ActionView::RecordIdentifier.dom_id(new_card)}"/, response.body)
  end

  test "regression: archive still broadcasts a remove, now alongside the card-count pill" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch archive_card_url(@card)
    end

    assert_equal [
      ["remove",  ActionView::RecordIdentifier.dom_id(@card)],
      ["replace", "list_#{@card.list_id}_card_count"]
    ].sort, broadcast_targets(broadcasts).sort
  end

  # --- start_date via the due popover ---

  test "update sets a start date alongside the due date" do
    patch card_url(@card), params: { card: { start_date: "2026-05-04T09:00", due_date: "2026-05-06T17:00" } }, as: :turbo_stream

    assert_response :success
    @card.reload
    assert_equal Time.zone.parse("2026-05-04T09:00"), @card.start_date
    assert_equal Time.zone.parse("2026-05-06T17:00"), @card.due_date
  end

  test "update clears the start date with a blank value" do
    @card.update!(start_date: 2.days.from_now, due_date: 5.days.from_now)

    patch card_url(@card), params: { card: { start_date: "" } }, as: :turbo_stream

    assert_response :success
    assert_nil @card.reload.start_date
  end

  test "update rejects a start date after the due date and saves nothing" do
    @card.update!(start_date: nil, due_date: Time.zone.parse("2026-05-06T17:00"))

    patch card_url(@card), params: { card: { start_date: "2026-05-10T09:00", due_date: "2026-05-06T17:00" } }, as: :turbo_stream

    # 200 rather than 422 on purpose — see CardsController#update's failure
    # branch: Turbo drops a 4xx turbo-stream response for this frame-targeted
    # form, so the inline error would never reach the user.
    assert_response :success
    @card.reload
    assert_nil @card.start_date, "invalid start date must not persist"
    assert_equal Time.zone.parse("2026-05-06T17:00"), @card.due_date
    assert_match "on or before the due date", response.body
    assert_match(/turbo-stream action="replace" target="modal"/, response.body)
  end

  test "the due popover offers a start date field" do
    get card_url(@card)

    assert_response :success
    assert_match(/name="card\[start_date\]"/, response.body)
    assert_match "Start date", response.body
  end

  test "unarchive broadcasts the restored card above the add-card trigger, not appended to the container" do
    @card.archive!
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch unarchive_card_url(@card)
    end

    assert_equal [
      ["before",  "list_#{@card.list_id}_new_card"],
      ["replace", "list_#{@card.list_id}_card_count"]
    ].sort, broadcast_targets(broadcasts).sort

    # The "Add a card" trigger and the gap-inserter overlay both live INSIDE
    # list_X_cards, so an append landed the restored card below them.
    insert = broadcast_for(broadcasts, "list_#{@card.list_id}_new_card")
    assert_no_match(/action="append" target="list_#{@card.list_id}_cards"/, insert)
    assert_match "id=\"#{ActionView::RecordIdentifier.dom_id(@card)}\"", insert
  end

  test "regression: update still broadcasts a replace to the board's stream" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch card_url(@card), params: { card: { title: "Updated via broadcast test" } }
    end

    # An update that doesn't move the card leaves both lists' counts alone, so
    # there's still exactly one broadcast here.
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]],
                 broadcast_targets(broadcasts)
  end

  # --- card-count pill: WIP limits update live on every count change ---

  test "archiving broadcasts a card-count pill showing the count going down" do
    @list_three.update!(card_limit: 2)
    @list_three.cards.create!(title: "Keeper")
    doomed = @list_three.cards.create!(title: "Doomed")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch archive_card_url(doomed)
    end

    pill = broadcast_for(broadcasts, "list_#{@list_three.id}_card_count")
    assert pill, "expected a card-count pill broadcast"
    assert_match(/1\s*\/\s*2/, pill)
    assert_match(/data-card-limit-state="ok"/, pill)
  end

  test "creating a card past the limit broadcasts a pill in the over-limit state" do
    @list_three.update!(card_limit: 2)
    2.times { |i| @list_three.cards.create!(title: "C#{i}") }
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      post list_cards_url(@list_three), params: { card: { title: "Tips It Over" } }, as: :turbo_stream
    end

    pill = broadcast_for(broadcasts, "list_#{@list_three.id}_card_count")
    assert pill, "expected a card-count pill broadcast"
    # The whole point of the fix: 2/2 -> 3/2 with no reload.
    assert_match(/3\s*\/\s*2/, pill)
    assert_match(/data-card-limit-state="over"/, pill)
  end

  test "unarchiving broadcasts a card-count pill showing the count going up" do
    @list_three.update!(card_limit: 2)
    restored = @list_three.cards.create!(title: "Restored")
    restored.archive!
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch unarchive_card_url(restored)
    end

    pill = broadcast_for(broadcasts, "list_#{@list_three.id}_card_count")
    assert pill, "expected a card-count pill broadcast"
    assert_match(/1\s*\/\s*2/, pill)
  end

  # --- live card moves: full list replace for source + destination ---
  #
  # A drag can drop a card ANYWHERE mid-list, so these paths broadcast a full
  # list replace rather than broadcast_card_insert (which targets `before` the
  # "Add a card" trigger and therefore always lands at the bottom). The list
  # partial renders cards in position order, so arbitrary drop positions come
  # out right, and the header — including list_X_card_count — re-renders with it.

  test "move between lists broadcasts a list replace for source and destination, and nothing else" do
    source = @list_one
    destination = @list_three
    mover = source.cards.create!(title: "Mover")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch move_card_url(mover), params: { card: { list_id: destination.id, position: 1 } }, as: :json
    end

    assert_equal [
      ["replace", "list_#{source.id}"],
      ["replace", "list_#{destination.id}"]
    ].sort, broadcast_targets(broadcasts).sort

    targets = broadcast_targets(broadcasts)
    # A bare card replace would re-render the card in place in its OLD list, so
    # it must be gone from this path entirely.
    assert_not_includes targets, ["replace", ActionView::RecordIdentifier.dom_id(mover)]
    # The pill now rides the list replace; a separate one would be a duplicate.
    assert_not_includes targets, ["replace", "list_#{source.id}_card_count"]
    assert_not_includes targets, ["replace", "list_#{destination.id}_card_count"]
  end

  test "move between lists still refreshes both count pills via the list replaces" do
    source = @list_one
    destination = @list_three
    source.update!(card_limit: 5)
    destination.update!(card_limit: 5)
    mover = source.cards.create!(title: "Mover")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch move_card_url(mover), params: { card: { list_id: destination.id, position: 1 } }, as: :json
    end

    assert_match(/id="list_#{source.id}_card_count"/, broadcast_for(broadcasts, "list_#{source.id}"))
    assert_match(/id="list_#{destination.id}_card_count"/, broadcast_for(broadcasts, "list_#{destination.id}"))
  end

  test "move within one list broadcasts exactly one list replace" do
    a = @list_three.cards.create!(title: "A")
    @list_three.cards.create!(title: "B")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch move_card_url(a), params: { card: { list_id: @list_three.id, position: 2 } }, as: :json
    end

    assert_equal [["replace", "list_#{@list_three.id}"]], broadcast_targets(broadcasts),
                 "a same-list move must dedupe down to one list replace"
  end

  test "move broadcasts the destination list with the cards in their new order" do
    destination = @list_three
    first  = destination.cards.create!(title: "ZZ First")
    second = destination.cards.create!(title: "YY Second")
    mover  = @list_one.cards.create!(title: "XX Mover")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    # Drop into the MIDDLE of the destination (position 2 of 3).
    broadcasts = capture_broadcasts(stream_name) do
      patch move_card_url(mover), params: { card: { list_id: destination.id, position: 2 } }, as: :json
    end

    assert_equal 2, mover.reload.position
    assert_equal ["ZZ First", "XX Mover", "YY Second"], destination.reload.active_cards.map(&:title)

    # The broadcast body must actually reflect the reorder, not merely exist.
    body = broadcast_for(broadcasts, "list_#{destination.id}")
    order = [first, mover, second].map { |c| body.index(%(id="#{ActionView::RecordIdentifier.dom_id(c)}")) }
    assert_equal order.compact, order, "all three cards should be in the broadcast"
    assert_equal order.sort, order, "broadcast must render cards in the new position order"
  end

  test "move within a list broadcasts the reordered list body" do
    a = @list_three.cards.create!(title: "AA Card")
    b = @list_three.cards.create!(title: "BB Card")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch move_card_url(a), params: { card: { list_id: @list_three.id, position: 2 } }, as: :json
    end

    assert_equal ["BB Card", "AA Card"], @list_three.reload.active_cards.map(&:title)

    body = broadcast_for(broadcasts, "list_#{@list_three.id}")
    assert_operator body.index(%(id="#{ActionView::RecordIdentifier.dom_id(b)}")), :<,
                    body.index(%(id="#{ActionView::RecordIdentifier.dom_id(a)}")),
                    "reordering must be visible in the broadcast body"
  end

  test "update with a list change broadcasts the two list replaces and no bare card replace" do
    source = @list_one
    destination = @list_three
    mover = source.cards.create!(title: "Modal Mover")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch card_url(mover), params: { card: { list_id: destination.id, position: "bottom" } }, as: :turbo_stream
    end

    targets = broadcast_targets(broadcasts)
    assert_includes targets, ["replace", "list_#{source.id}"]
    assert_includes targets, ["replace", "list_#{destination.id}"]
    # The old behaviour re-rendered the card at its own dom_id, which left it
    # sitting in the source list for every other viewer.
    assert_not_includes targets, ["replace", ActionView::RecordIdentifier.dom_id(mover)]
    assert_not_includes targets, ["replace", "list_#{source.id}_card_count"]
    assert_not_includes targets, ["replace", "list_#{destination.id}_card_count"]
  end

  test "regression: update without a list change still broadcasts exactly one card replace" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      patch card_url(@card), params: { card: { title: "Plain Edit" } }, as: :turbo_stream
    end

    # The common edit path must not gain list replaces.
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]],
                 broadcast_targets(broadcasts)
  end

  test "move query count stays flat as the lists' card counts grow" do
    small = count_queries_for_card_move(cards_per_list: 3)
    large = count_queries_for_card_move(cards_per_list: 6)

    assert_equal small, large, "query count must not grow with card count (N+1 regression)"
  end

  test "destroying a card broadcasts its list's card-count pill" do
    doomed = @list_three.cards.create!(title: "Hard Deleted")
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream_name) do
      delete card_url(doomed)
    end

    assert_includes broadcast_targets(broadcasts), ["replace", "list_#{@list_three.id}_card_count"]
  end

  test "the card-count pill element renders even when no limit is set, so the broadcast has a target" do
    @list_three.update!(card_limit: nil)

    get board_url(@board_one)

    assert_response :success
    # The element must always exist — a turbo_stream replace against a missing
    # target is silently dropped.
    assert_match(/id="list_#{@list_three.id}_card_count"/, response.body)
    # ...but it carries no limit state and no visible count.
    assert_no_match(/data-card-limit-state/, response.body)
  end

  test "the actor's own create response does not contain the pill markup (anti double-render)" do
    @list_three.update!(card_limit: 2)

    post list_cards_url(@list_three), params: { card: { title: "No Dup Pill" } }, as: :turbo_stream

    assert_response :success
    assert_no_match(/list_#{@list_three.id}_card_count/, response.body)
  end

  private

  # [[action, target], ...] for a captured broadcast list, one pair per
  # broadcast. Asserting on targets (rather than just counting) is what lets a
  # test distinguish a legitimate extra broadcast from a duplicated one.
  def broadcast_targets(broadcasts)
    broadcasts.map do |payload|
      payload.match(/<turbo-stream action="([^"]+)" target="([^"]+)"/).captures
    end
  end

  # The single captured broadcast aimed at `target`, or nil.
  def broadcast_for(broadcasts, target)
    broadcasts.find { |payload| payload.include?(%(target="#{target}")) }
  end

  # A cross-list move renders BOTH lists in full (every cards/_card in each), so
  # this is the guard on the move broadcast's preload. Fresh user + sign-in per
  # measurement: reusing one Warden session across two requests adds a
  # session-revalidation query that has nothing to do with card count.
  def count_queries_for_card_move(cards_per_list:)
    user = User.create!(email: "moveperf#{cards_per_list}@example.com", password: "password")
    sign_in user

    board = user.boards.create!(name: "Move Perf Board #{cards_per_list}")
    board.lists.destroy_all
    source = board.lists.create!(name: "Source", position: 1)
    destination = board.lists.create!(name: "Destination", position: 2)

    # Cards on both sides, each with the association tree cards/_card touches,
    # so a missing include shows up as growth on either list's render.
    [source, destination].each do |list|
      cards_per_list.times do |i|
        card = list.cards.create!(title: "#{list.name} #{i}")
        card.checklists.create!(title: "CL", position: 1).checklist_items.create!(content: "item", position: 1)
        card.labels << board.labels.create!(name: "L#{list.id}#{i}", color: "blue")
      end
    end

    mover = source.cards.create!(title: "Mover")

    result = count_queries do
      patch move_card_url(mover), params: { card: { list_id: destination.id, position: 1 } }, as: :json
    end
    assert_response :success
    sign_out user
    result
  end
end
