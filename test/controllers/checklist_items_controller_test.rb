require "test_helper"

class ChecklistItemsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @card = cards(:one)
    @checklist = checklists(:one)
    @checklist_item = checklist_items(:one)
    sign_in @user
  end

  # --- board-tile broadcast ---
  #
  # cards/_card renders a checklist progress badge (items_done/items_total from
  # the eager-loaded checklists), so every item create/toggle/delete changes what
  # each board viewer sees. Same reason CardLabelsController, CardMembersController
  # and AttachmentsController broadcast the re-rendered tile.
  #
  # No double render: all three actions' own turbo_stream responses target
  # checklist_item_<id> / checklist_<id> — modal-internal ids, never the tile.
  #
  # Scope is the board tile only. Viewers with the card MODAL open still don't see
  # the checklist section itself change — same out-of-scope call as attachments.
  #
  # The assertions below check the badge's rendered VALUE, not merely that a
  # broadcast fired: a broadcast carrying stale content passes a naive test (see
  # the attachment-destroy cover bug).

  def board_stream
    Turbo::StreamsChannel.send(:stream_name_from, @card.list.board)
  end

  def card_target
    ActionView::RecordIdentifier.dom_id(@card)
  end

  # The tile as it would render right now, straight from the DB.
  def render_tile
    ApplicationController.render(partial: "cards/card", locals: { card: Card.find(@card.id) })
  end

  # The tile badge renders as `<i class="fa-solid fa-square-check"></i>N/M`.
  def assert_tile_progress(expected, body)
    assert_match(%r{fa-square-check[^>]*></i>\s*#{Regexp.escape(expected)}}, body,
                 "expected the broadcast tile to show checklist progress #{expected}")
  end

  test "toggling an item complete broadcasts exactly one card replace carrying the new progress" do
    assert_equal 1, @card.checklists.sum { |cl| cl.checklist_items.size }
    assert_not @checklist_item.completed

    broadcasts = capture_broadcasts(board_stream) do
      patch card_checklist_checklist_item_url(@card, @checklist, @checklist_item),
            params: { checklist_item: { completed: true } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", card_target]], broadcast_targets(broadcasts)

    body = broadcast_for(broadcasts, card_target)
    assert_tile_progress "1/1", body
    assert_no_match(%r{fa-square-check[^>]*></i>\s*0/1}, body,
                    "the tile must not carry the pre-toggle progress")
  end

  test "un-toggling an item broadcasts the decremented progress" do
    @checklist_item.update!(completed: true)

    broadcasts = capture_broadcasts(board_stream) do
      patch card_checklist_checklist_item_url(@card, @checklist, @checklist_item),
            params: { checklist_item: { completed: false } }, as: :turbo_stream
    end

    assert_equal [["replace", card_target]], broadcast_targets(broadcasts)
    assert_tile_progress "0/1", broadcast_for(broadcasts, card_target)
  end

  test "creating an item broadcasts exactly one card replace carrying the new total" do
    broadcasts = capture_broadcasts(board_stream) do
      post card_checklist_checklist_items_url(@card, @checklist),
           params: { checklist_item: { content: "Second" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", card_target]], broadcast_targets(broadcasts)
    assert_tile_progress "0/2", broadcast_for(broadcasts, card_target)
  end

  test "deleting the last item broadcasts a tile with no progress badge at all" do
    broadcasts = capture_broadcasts(board_stream) do
      delete card_checklist_checklist_item_url(@card, @checklist, @checklist_item), as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", card_target]], broadcast_targets(broadcasts)
    # items_total drops to 0, and the badge is wrapped in `if items_total.positive?`.
    assert_no_match(/fa-square-check/, broadcast_for(broadcasts, card_target),
                    "with no items left the tile must not render a progress badge")
  end

  test "adding the first item to a card with no checklist items adds the badge" do
    @checklist.checklist_items.destroy_all
    assert_no_match(/fa-square-check/, render_tile, "precondition: no badge yet")

    broadcasts = capture_broadcasts(board_stream) do
      post card_checklist_checklist_items_url(@card, @checklist),
           params: { checklist_item: { content: "First" } }, as: :turbo_stream
    end

    assert_tile_progress "0/1", broadcast_for(broadcasts, card_target)
  end

  test "the actor's own response does not contain the board tile (anti double-render)" do
    patch card_checklist_checklist_item_url(@card, @checklist, @checklist_item),
          params: { checklist_item: { completed: true } }, as: :turbo_stream

    assert_response :success
    assert_no_match(/target="#{card_target}"/, response.body)
  end


  test "should create checklist_item" do
    assert_difference('ChecklistItem.count') do
      post card_checklist_checklist_items_url(@card, @checklist), params: { checklist_item: { content: 'New Item' } }
    end
    assert_redirected_to board_url(@card.list.board)
  end

  test "should update checklist_item" do
    patch card_checklist_checklist_item_url(@card, @checklist, @checklist_item), params: { checklist_item: { completed: true } }
    assert_redirected_to board_url(@card.list.board)
    assert @checklist_item.reload.completed
  end

  test "should destroy checklist_item" do
    assert_difference('ChecklistItem.count', -1) do
      delete card_checklist_checklist_item_url(@card, @checklist, @checklist_item)
    end
    assert_redirected_to board_url(@card.list.board)
  end

  test "should not create checklist_item on a checklist the user has no access to" do
    other_card = cards(:two)
    other_checklist = checklists(:two)

    assert_no_difference('ChecklistItem.count') do
      post card_checklist_checklist_items_url(other_card, other_checklist), params: { checklist_item: { content: 'Injected' } }
    end
    assert_response :not_found
  end

  test "should not update a checklist_item belonging to a checklist the user has no access to" do
    other_card = cards(:two)
    other_checklist = checklists(:two)
    other_item = checklist_items(:two)

    patch card_checklist_checklist_item_url(other_card, other_checklist, other_item), params: { checklist_item: { completed: true } }

    assert_response :not_found
    assert_not other_item.reload.completed
  end

  # --- validation failure keeps the user in the card modal ---
  #
  # Blank content used to redirect to the board with "Could not add item" — out of
  # the modal, for a validation error. Not reachable from the app's own UI today
  # (the "Add an item" field carries `required: true`), but one markup change away,
  # and the branch existed either way.
  #
  # `as: :turbo_stream` does NOT send a turbo-stream request; the raw Accept header
  # is what exercises the branch the browser hits.
  TURBO_STREAM_ONLY = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  test "blank item content conveys the error without redirecting or 500ing" do
    assert_no_difference("ChecklistItem.count") do
      post card_checklist_checklist_items_url(@card, @checklist),
           params: { checklist_item: { content: "" } }, headers: TURBO_STREAM_ONLY
    end

    # 200, not 422: the form is frame-targeted at the checklist's items frame, and
    # Turbo drops a 4xx turbo-stream response for a frame-targeted submission.
    assert_response :success
    assert_match(/turbo-stream/, response.body)
    assert_match(/<turbo-stream action="replace" target="flash"/, response.body)
    assert_match(/can&#39;t be blank|can't be blank/, response.body,
                 "the error must actually reach the user")
  end

  test "blank item content does not broadcast a tile" do
    stream = Turbo::StreamsChannel.send(:stream_name_from, @card.list.board)

    broadcasts = capture_broadcasts(stream) do
      post card_checklist_checklist_items_url(@card, @checklist),
           params: { checklist_item: { content: "" } }, headers: TURBO_STREAM_ONLY
    end

    assert_empty broadcasts, "a rejected create must not push a tile to other viewers"
  end

  test "blank item content falls back to a redirect carrying the model's error for HTML" do
    assert_no_difference("ChecklistItem.count") do
      post card_checklist_checklist_items_url(@card, @checklist),
           params: { checklist_item: { content: "" } }, headers: { "Accept" => "text/html" }
    end

    assert_redirected_to board_url(@card.list.board)
    assert_match(/can't be blank/, flash[:alert], "not the old generic copy")
  end

  test "should not destroy a checklist_item id that belongs to a different checklist than the one in the path" do
    foreign_item = checklist_items(:two) # belongs to checklists(:two)

    assert_no_difference('ChecklistItem.count') do
      delete card_checklist_checklist_item_url(@card, @checklist, foreign_item)
    end
    assert_response :not_found
  end
end
