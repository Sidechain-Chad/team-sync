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

  # --- empty card feed placeholder ---
  #
  # #activities_and_comments is the broadcast_prepend_to target for both Comment
  # and Activity, so the placeholder inside it is rendered UNCONDITIONALLY and
  # hidden by CSS whenever it isn't :only-child. These tests exist to stop someone
  # "tidying up" by reintroducing an `if @feed.empty?` — which would go stale the
  # instant a live comment was prepended beside it.

  test "a card with no comments or activity renders the feed placeholder" do
    empty_card = @list_one.cards.create!(title: "Nothing here yet")
    assert_equal 0, Comment.where(card: empty_card).count
    assert_equal 0, Activity.where(card: empty_card).count

    get card_url(empty_card)

    assert_response :success
    assert_select "#activities_and_comments > .feed-empty", count: 1
    assert_select "#activities_and_comments > .feed-empty p", text: "No comments or activity yet."
    # Nothing else inside — so the placeholder really is :only-child and visible.
    assert_select "#activities_and_comments > *", count: 1
  end

  test "a card WITH feed items still renders the placeholder markup — CSS hides it, not a conditional" do
    # Counted straight off the DB, not via @card.comments.empty? — comments_count
    # is a counter cache and cards.yml doesn't set it, so the association's
    # own #empty? trusts a stale 0 and reports "no comments" for a card that
    # demonstrably has one. (The view is unaffected: @feed builds with `+`,
    # which forces a real load.)
    assert_equal 1, Comment.where(card: @card).count, "fixture precondition: cards(:one) has a comment"
    assert_equal 1, Activity.where(card: @card).count, "fixture precondition: cards(:one) has an activity"

    get card_url(@card)

    assert_response :success
    # Both present: the placeholder is unconditional, and it now has siblings, so
    # `.feed-empty:not(:only-child)` hides it in the browser.
    assert_select "#activities_and_comments > .feed-empty", count: 1
    assert_select "#activities_and_comments > ##{ActionView::RecordIdentifier.dom_id(Comment.where(card: @card).first)}", count: 1
    assert_select "#activities_and_comments > .automated-activity", count: Activity.where(card: @card).count
    assert_select "#activities_and_comments > *", minimum: 3
  end

  test "the placeholder is the only non-feed element in the container, which :only-child depends on" do
    get card_url(@card)

    assert_response :success
    # Every element child is either a feed item or the placeholder. If a
    # structural wrapper is ever added in here, :only-child breaks and the
    # placeholder silently never shows again.
    assert_select "#activities_and_comments > *" do |children|
      children.each do |child|
        classes = child["class"].to_s
        assert child["id"].to_s.start_with?("comment_") ||
               classes.include?("automated-activity") ||
               classes.include?("feed-empty"),
               "unexpected element in #activities_and_comments: #{child.name} class=#{classes.inspect} id=#{child["id"].inspect}"
      end
    end
  end

  test "the comment prepend broadcast is unchanged — comment partial only, no placeholder" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @card)

    broadcasts = capture_broadcasts(stream) do
      @card.comments.create!(content: "Live one", user: @user)
    end

    assert_equal [["prepend", "activities_and_comments"]], broadcast_targets(broadcasts)
    body = broadcast_for(broadcasts, "activities_and_comments")
    assert_match(/id="#{ActionView::RecordIdentifier.dom_id(Comment.last)}"/, body)
    assert_match(/Live one/, body)
    assert_no_match(/feed-empty/, body,
                    "the prepend must stay exactly what it was — CSS does the hiding, not the broadcast")
  end

  test "the activity prepend broadcast is unchanged — activity partial only, no placeholder" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @card)

    broadcasts = capture_broadcasts(stream) do
      @card.log_activity(@user, "updated", "Live activity")
    end

    assert_equal [["prepend", "activities_and_comments"]], broadcast_targets(broadcasts)
    body = broadcast_for(broadcasts, "activities_and_comments")
    assert_match(/automated-activity/, body)
    assert_no_match(/feed-empty/, body,
                    "the prepend must stay exactly what it was — CSS does the hiding, not the broadcast")
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

  # cards/edit_description exists only as HTML, so `render :edit_description` in
  # update_description's failure branch raised MissingTemplate for a
  # turbo-stream-only Accept. Reaching that branch at all takes a card whose
  # PERSISTED row is already invalid — description itself has no validation, so
  # the only way to fail is a pre-existing start_date > due_date, which
  # update_column can produce (raw SQL, a data import, an older row). Rare, but a
  # 500 either way, and the success path here is a frame replace.
  test "update_description on an already-invalid card does not raise for a turbo-stream-only request" do
    # Bypass validation to persist the invalid state a normal write can't create.
    @card.update_column(:start_date, Time.utc(2026, 9, 1, 9, 0))
    @card.update_column(:due_date,   Time.utc(2026, 8, 1, 9, 0))
    assert_not Card.find(@card.id).valid?, "setup must leave the row invalid"

    patch update_description_card_url(@card), params: { card: { description: "New body" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # 200, not 422: the form is frame-targeted (the card's description frame), and
    # Turbo drops a 4xx turbo-stream response for a frame-targeted submission.
    assert_response :success
    assert_match(/turbo-stream/, response.body)
    assert_match(/must be on or before the due date/, response.body,
                 "the validation error must actually reach the user")
  end

  test "update_description on an already-invalid card re-renders the form with 422 for HTML" do
    @card.update_column(:start_date, Time.utc(2026, 9, 1, 9, 0))
    @card.update_column(:due_date,   Time.utc(2026, 8, 1, 9, 0))

    patch update_description_card_url(@card), params: { card: { description: "New body" } },
          headers: { "Accept" => "text/html" }

    assert_response :unprocessable_entity
  end

  # The duplicate-risk guard for the attachment broadcast work.
  #
  # #update ALREADY broadcasts a card replace for any non-move update, and that
  # broadcast fires AFTER CardAttachmentService runs — so the modal's "Attach"
  # form was already covered, and adding a second broadcast here would have given
  # the actor two. `replace` is idempotent by id so it wouldn't visibly duplicate,
  # but it doubles the render and would break these count-by-target assertions.
  # AttachmentsController#create/#destroy were the genuinely uncovered paths.

  test "attaching via the modal broadcasts exactly ONE card replace, not two" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)
    file = fixture_file_upload("test.png", "image/png")

    broadcasts = capture_broadcasts(stream) do
      patch card_url(@card), params: { card: { attachments: [file] } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts),
                 "one replace — #update's own broadcast, with no second one added"
  end

  test "the modal attach broadcast reflects the new attachment" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)
    file = fixture_file_upload("test.png", "image/png")

    broadcasts = capture_broadcasts(stream) do
      patch card_url(@card), params: { card: { attachments: [file] } }, as: :turbo_stream
    end

    # The broadcast is emitted after the service attaches, so the re-rendered
    # tile already carries the paperclip badge.
    assert_match(/fa-paperclip/, broadcast_for(broadcasts, ActionView::RecordIdentifier.dom_id(@card)))
  end

  # --- inline title edit (#edit_title / #update_title) ---
  #
  # The tile and the modal can both be showing the same card at once (the modal
  # opens over the board), so they render into SEPARATE frames and the two
  # responses are deliberately different shapes: from the tile the broadcast
  # already brings the title back to display mode for the actor, so the actor's
  # own response must render nothing; from the modal the response replaces the
  # modal title frame, a different target from the broadcast's tile.

  TILE_TITLE_FRAME  = ->(card) { ActionView::RecordIdentifier.dom_id(card, :tile_title) }
  MODAL_TITLE_FRAME = ->(card) { ActionView::RecordIdentifier.dom_id(card, :modal_title) }

  test "edit_title renders the form into the TILE title frame" do
    get edit_title_card_url(@card, context: "tile")

    assert_response :success
    assert_select "turbo-frame##{TILE_TITLE_FRAME.call(@card)} input[name=?]", "card[title]"
    assert_select "turbo-frame##{MODAL_TITLE_FRAME.call(@card)}", count: 0
    # Blur saves, mirroring the list-rename pattern.
    assert_match(/blur-&gt;autosubmit#submit|blur->autosubmit#submit/, response.body)
  end

  test "edit_title renders the form into the MODAL title frame" do
    get edit_title_card_url(@card, context: "modal")

    assert_response :success
    assert_select "turbo-frame##{MODAL_TITLE_FRAME.call(@card)} input[name=?]", "card[title]"
    assert_select "turbo-frame##{TILE_TITLE_FRAME.call(@card)}", count: 0
  end

  test "edit_title with an unrecognised context falls back to the tile frame" do
    get edit_title_card_url(@card, context: "bogus")

    assert_response :success
    assert_select "turbo-frame##{TILE_TITLE_FRAME.call(@card)} input[name=?]", "card[title]"
  end

  test "edit_title is scoped: another user's card 404s" do
    other = cards(:two) # lives on boards(:two), which @user cannot access

    get edit_title_card_url(other, context: "tile")

    assert_response :not_found
  end

  test "update_title saves and broadcasts exactly one tile replace carrying the NEW title" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)
    original = @card.title

    broadcasts = capture_broadcasts(stream) do
      patch update_title_card_url(@card, context: "tile"),
            params: { card: { title: "Renamed Inline" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "Renamed Inline", @card.reload.title
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
    # Not merely "a broadcast fired" — the BODY has to carry the new title. A
    # broadcast rendered from a stale record passes a naive count assertion
    # while showing every other viewer the old value (the attachment-destroy
    # lesson).
    body = broadcast_for(broadcasts, ActionView::RecordIdentifier.dom_id(@card))
    assert_match(/Renamed Inline/, body)
    assert_no_match(/#{Regexp.escape(original)}<\/h4>/, body)
  end

  test "update_title from the MODAL also broadcasts exactly one tile replace with the new title" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream) do
      patch update_title_card_url(@card, context: "modal"),
            params: { card: { title: "Renamed From Modal" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "Renamed From Modal", @card.reload.title
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
    assert_match(/Renamed From Modal/, broadcast_for(broadcasts, ActionView::RecordIdentifier.dom_id(@card)))
  end

  test "the actor's own TILE response renders no tile markup (anti double-render)" do
    patch update_title_card_url(@card, context: "tile"),
          params: { card: { title: "Tile Actor" } }, as: :turbo_stream

    assert_response :success
    # The broadcast replaces the whole tile for everyone including the actor, so
    # this response deliberately carries nothing — not the tile, not the
    # tile-title frame. Swapping the frame back here too would replace it twice.
    assert_no_match(/turbo-stream/, response.body)
    assert_no_match(/#{TILE_TITLE_FRAME.call(@card)}/, response.body)
    assert_no_match(/id="#{ActionView::RecordIdentifier.dom_id(@card)}"/, response.body)
  end

  test "the actor's own MODAL response replaces the modal title frame" do
    patch update_title_card_url(@card, context: "modal"),
          params: { card: { title: "Modal Actor" } }, as: :turbo_stream

    assert_response :success
    assert_match(/<turbo-stream action="replace" target="#{MODAL_TITLE_FRAME.call(@card)}"/, response.body)
    assert_match(/Modal Actor/, response.body)
    # A different target from the broadcast's tile, so the two never collide.
    assert_no_match(/target="#{ActionView::RecordIdentifier.dom_id(@card)}"/, response.body)
  end

  test "update_title logs a renamed activity, but not for a no-op blur save" do
    assert_difference -> { @card.activities.where(action: "renamed").count }, 1 do
      patch update_title_card_url(@card, context: "tile"),
            params: { card: { title: "Logged Rename" } }, as: :turbo_stream
    end
    assert_equal "Logged Rename", @card.reload.activities.where(action: "renamed").last.description

    # Blur saves, so "open the editor, click away" re-submits the same title
    # constantly — those must not each write a history row.
    assert_no_difference -> { @card.activities.where(action: "renamed").count } do
      patch update_title_card_url(@card, context: "tile"),
            params: { card: { title: "Logged Rename" } }, as: :turbo_stream
    end
  end

  test "a no-op title save still broadcasts, so the tile leaves edit mode" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream) do
      patch update_title_card_url(@card, context: "tile"),
            params: { card: { title: @card.title } }, as: :turbo_stream
    end

    # In the tile context the broadcast is the ONLY thing that swaps the input
    # back for the heading, so it cannot be conditional on the title changing.
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
  end

  # Blank title. Validation is `presence`, and the real UI submits from inside a
  # turbo frame — note `as: :turbo_stream` does NOT send a turbo-stream request,
  # so these use the raw Accept header where that path matters.

  test "a blank title from the TILE is rejected, keeps the old title, and surfaces the error" do
    original = @card.title

    patch update_title_card_url(@card, context: "tile"),
          params: { card: { title: "" } }, headers: TURBO_STREAM_ONLY

    # 200, not 422: Turbo drops a 4xx turbo-stream response for a
    # frame-targeted submission, so the error would never be seen.
    assert_response :success
    assert_equal original, @card.reload.title
    # Reverted to display mode with the OLD title, rejected value discarded.
    assert_match(/<turbo-stream action="replace" target="#{TILE_TITLE_FRAME.call(@card)}"/, response.body)
    assert_match(/<turbo-stream action="replace" target="flash"/, response.body)
    assert_match(/can&#39;t be blank|can't be blank/, response.body)
  end

  test "a blank title from the MODAL is rejected and surfaces the error" do
    original = @card.title

    patch update_title_card_url(@card, context: "modal"),
          params: { card: { title: "" } }, headers: TURBO_STREAM_ONLY

    assert_response :success
    assert_equal original, @card.reload.title
    assert_match(/<turbo-stream action="replace" target="#{MODAL_TITLE_FRAME.call(@card)}"/, response.body)
    assert_match(/can&#39;t be blank|can't be blank/, response.body)
  end

  test "a blank title broadcasts nothing" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream) do
      patch update_title_card_url(@card, context: "tile"),
            params: { card: { title: "" } }, headers: TURBO_STREAM_ONLY
    end

    assert_empty broadcasts, "a rejected rename must not push a tile to other viewers"
  end

  test "a blank title re-renders the form with 422 for an HTML request" do
    original = @card.title

    patch update_title_card_url(@card, context: "tile"),
          params: { card: { title: "" } }, headers: { "Accept" => "text/html" }

    # HTML form re-render keeps 422 — Turbo needs a 4xx to re-render a form.
    assert_response :unprocessable_entity
    assert_equal original, @card.reload.title
    assert_select "turbo-frame##{TILE_TITLE_FRAME.call(@card)} input[name=?]", "card[title]"
  end

  test "update_title is scoped: another user's card 404s" do
    other = cards(:two)
    original = other.title

    patch update_title_card_url(other, context: "tile"), params: { card: { title: "Hijacked" } }

    # Cross-tenant requests 404 (RecordNotFound), never 403.
    assert_response :not_found
    assert_equal original, other.reload.title
  end

  # --- the aria-labelledby target must survive BOTH modes ---
  #
  # cards/show.html.erb's dialog is labelled by card_modal_title_<id>. That id
  # used to live on the <h2>, which the title frame replaces with a form in edit
  # mode — the dialog would have lost its accessible name. It now lives on the
  # enclosing wrapper, outside the frame.

  test "the modal's aria-labelledby target exists in display mode" do
    get card_url(@card)

    assert_response :success
    assert_match(/aria-labelledby="card_modal_title_#{@card.id}"/, response.body)
    assert_match(/id="card_modal_title_#{@card.id}"/, response.body)
    # The id is on the wrapper, NOT on the heading the frame swaps out.
    assert_no_match(/<h2 id="card_modal_title_#{@card.id}"/, response.body)
  end

  # Found in the accessibility tree, not by reading the markup: the title link
  # first carried aria-label="Edit card title", and because aria-labelledby
  # computes the dialog's name from the wrapper's SUBTREE — where a descendant's
  # aria-label beats its own text content — the dialog announced as "Edit card
  # title" instead of the card's title. The link wraps the heading text, so it is
  # not icon-only and needs no label; `title` carries the hint instead.
  test "the modal title link has no aria-label, so it can't hijack the dialog's name" do
    get card_url(@card)

    assert_response :success
    assert_select "turbo-frame##{MODAL_TITLE_FRAME.call(@card)} a" do |links|
      assert_equal 1, links.size
      assert_nil links.first["aria-label"],
                 "an aria-label here overrides the heading text in the dialog's accessible name"
      assert_equal "Rename card", links.first["title"]
    end
    # The name the dialog resolves to is the heading text inside the wrapper.
    assert_select "##{"card_modal_title_#{@card.id}"} h2", text: @card.title
  end

  test "the aria-labelledby target is outside the title frame, so edit mode keeps it" do
    get card_url(@card)
    body = response.body

    wrapper_at = body.index(%(id="card_modal_title_#{@card.id}"))
    frame_at   = body.index(%(id="#{MODAL_TITLE_FRAME.call(@card)}"))

    assert wrapper_at, "the aria-labelledby target must be rendered"
    assert frame_at, "the modal title frame must be rendered"
    assert wrapper_at < frame_at,
           "the labelling id must enclose the title frame, or it vanishes in edit mode"

    # And the edit render (which replaces only the frame) must not carry it —
    # proof the id is untouched by the swap rather than duplicated.
    get edit_title_card_url(@card, context: "modal")
    assert_no_match(/id="card_modal_title_#{@card.id}"/, response.body)
  end

  test "the tile's title still links to the card in display mode" do
    get board_url(@board_one)

    assert_response :success
    assert_select "turbo-frame##{TILE_TITLE_FRAME.call(@card)} a[href=?]", card_path(@card)
    assert_select "turbo-frame##{TILE_TITLE_FRAME.call(@card)} h4", text: @card.title
  end

  test "the tile's pencil enters inline rename rather than opening the modal" do
    get board_url(@board_one)

    assert_response :success
    assert_select "a[href=?][data-turbo-frame=?]",
                  edit_title_card_path(@card, context: "tile"),
                  TILE_TITLE_FRAME.call(@card)
    assert_select "a[aria-label=?]", "Rename card"
    # The old redundant "Edit card" pencil (which just opened the modal, the
    # same as clicking the card body) is gone.
    assert_select "a[aria-label=?]", "Edit card", count: 0
  end

  TURBO_STREAM_ONLY = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  # --- #toggle_watch ---
  #
  # Watching is per-user state only, so unlike almost every other card action this
  # one broadcasts NOTHING: cards/_card goes to the board stream, where every
  # viewer receives identical HTML, so per-user state must never be rendered into
  # it. That's asserted below and is also why there's no tile indicator in v1.

  test "toggle_watch starts watching and swaps the control to the watching state" do
    assert_difference -> { CardWatcher.count }, 1 do
      patch toggle_watch_card_url(@card), as: :turbo_stream
    end

    assert_response :success
    assert @card.reload.watched_by?(@user)
    assert_includes @card.watchers, @user
    assert_match(/<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(@card, :watch)}"/, response.body)
    assert_match(/Stop watching this card/, response.body)
  end

  test "toggle_watch a second time stops watching" do
    patch toggle_watch_card_url(@card), as: :turbo_stream

    assert_difference -> { CardWatcher.count }, -1 do
      patch toggle_watch_card_url(@card), as: :turbo_stream
    end

    assert_response :success
    assert_not @card.reload.watched_by?(@user)
    assert_match(/Watch this card/, response.body)
  end

  test "watching does not make the user a card member" do
    # A card with no members of its own — @card arrives with card_members(:one)
    # already attaching @user, which would mask this.
    bare = @list_three.cards.create!(title: "Watch-only card")

    patch toggle_watch_card_url(bare), as: :turbo_stream

    assert_response :success
    assert_empty bare.reload.members, "watching must not create a membership"
    assert_equal [@user], bare.watchers
    assert_equal [@user], bare.subscribers
  end

  test "toggle_watch broadcasts NOTHING to the board stream" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)

    broadcasts = capture_broadcasts(stream) do
      patch toggle_watch_card_url(@card), as: :turbo_stream
    end

    assert_empty broadcasts,
                 "watching is per-user state — broadcasting it would show one user's state to every viewer"
  end

  test "toggle_watch is scoped: a card the user cannot reach 404s and is not watched" do
    other = cards(:two) # boards(:two), which @user has no access to

    assert_no_difference -> { CardWatcher.count } do
      patch toggle_watch_card_url(other), as: :turbo_stream
    end
    assert_response :not_found
  end

  test "the card modal renders the watch control reflecting the persisted state" do
    get card_url(@card)
    assert_response :success
    assert_select "form##{ActionView::RecordIdentifier.dom_id(@card, :watch)}"
    assert_select "button[aria-label=?]", "Watch this card"
    assert_select "button[aria-pressed=?]", "false"

    CardWatcher.create!(card: @card, user: @user)

    get card_url(@card)
    assert_select "button[aria-label=?]", "Stop watching this card"
    assert_select "button[aria-pressed=?]", "true"
  end

  # --- the tile watch badge: markup identical for everyone, state client-side ---
  #
  # The tile DOES carry a watch badge now, but it is byte-identical for every
  # viewer: always rendered, always hidden, no per-user state. Visibility comes
  # from #watched_cards (rendered in request context) via watch_badge_controller.
  # These are the assertions that protect that split; the reason it has to be a
  # split at all is that cards/_card is broadcast through
  # ApplicationController.renderer, which has no session.

  test "the tile renders the watch badge element, hidden, for a card the user does NOT watch" do
    get board_url(@board_one)

    assert_response :success
    tile = css_select("turbo-frame##{ActionView::RecordIdentifier.dom_id(@card)}").first.to_s
    assert_match(/data-controller="watch-badge"/, tile)
    assert_match(/data-watch-badge-card-id-value="#{@card.id}"/, tile)
    assert_match(/class="hidden items-center gap-1"/, tile,
                 "the badge must ship hidden — the browser decides, not the server")
  end

  test "the tile markup is IDENTICAL whether or not the viewer watches the card" do
    get board_url(@board_one)
    not_watching = css_select("turbo-frame##{ActionView::RecordIdentifier.dom_id(@card)}").first.to_s

    CardWatcher.create!(card: @card, user: @user)

    get board_url(@board_one)
    watching = css_select("turbo-frame##{ActionView::RecordIdentifier.dom_id(@card)}").first.to_s

    assert_equal not_watching, watching,
                 "per-user state in the tile would leak through broadcast_card_update to every viewer"
  end

  test "a broadcast tile body is identical for a watcher and a non-watcher" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board_one)
    target = ActionView::RecordIdentifier.dom_id(@card)

    # A rename is the cheapest thing that fires broadcast_card_update.
    plain = capture_broadcasts(stream) do
      patch update_title_card_url(@card, context: "tile"), params: { card: { title: "Broadcast A" } }, as: :turbo_stream
    end
    body_without_watch = broadcast_for(plain, target)

    CardWatcher.create!(card: @card, user: @user)

    watched = capture_broadcasts(stream) do
      patch update_title_card_url(@card, context: "tile"), params: { card: { title: "Broadcast A" } }, as: :turbo_stream
    end
    body_with_watch = broadcast_for(watched, target)

    assert_equal body_without_watch, body_with_watch,
                 "the broadcast body must not depend on the acting user's watch state"
    assert_match(/data-controller="watch-badge"/, body_with_watch,
                 "the badge must still be present in the broadcast body")
  end

  test "watched_cards renders only the current user's watched ids for THIS board" do
    other_board_card = cards(:one) # will be watched on board_one
    off_board = @list_three.cards.create!(title: "Also on board one")
    CardWatcher.create!(card: other_board_card, user: @user)

    get board_url(@board_one)

    assert_response :success
    ids = JSON.parse(css_select("#watched_cards").first["data-watched-card-ids"])
    assert_includes ids, other_board_card.id
    assert_not_includes ids, off_board.id
  end

  test "watched_cards is per-user: another user's page render has a different set" do
    CardWatcher.create!(card: @card, user: @user)

    get board_url(@board_one)
    mine = JSON.parse(css_select("#watched_cards").first["data-watched-card-ids"])
    assert_equal [@card.id], mine

    # A second board member who watches nothing.
    other = User.create!(email: "watch-badge-other@example.com", password: "password")
    @board_one.board_users.create!(user: other)
    sign_out @user
    sign_in other

    get board_url(@board_one)
    theirs = JSON.parse(css_select("#watched_cards").first["data-watched-card-ids"])
    assert_empty theirs, "one user's watch set must not appear on another user's page"
  end

  test "watched_cards excludes cards on boards the user cannot see" do
    foreign = cards(:two) # boards(:two), no access
    CardWatcher.create!(card: foreign, user: @user)

    get board_url(@board_one)

    ids = JSON.parse(css_select("#watched_cards").first["data-watched-card-ids"])
    assert_not_includes ids, foreign.id
  end

  test "toggle_watch replaces watched_cards with the updated id set" do
    patch toggle_watch_card_url(@card), as: :turbo_stream

    assert_response :success
    assert_match(/<turbo-stream action="replace" target="watched_cards"/, response.body)
    body = response.body
    assert_match(/data-watched-card-ids="\[#{@card.id}\]"/, body)

    patch toggle_watch_card_url(@card), as: :turbo_stream
    assert_match(/data-watched-card-ids="\[\]"/, response.body,
                 "unwatching must ship the shrunken set")
  end

  private

  # broadcast_targets / broadcast_for now live in test_helper — ListsController's
  # broadcast tests need the same two helpers, and one mechanism beats two copies.

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
