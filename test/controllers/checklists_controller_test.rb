require "test_helper"

class ChecklistsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @card = cards(:one)
    @checklist = checklists(:one)
    sign_in @user
  end

  # --- board-tile broadcast ---
  #
  # cards/_card renders a checklist progress badge, so adding or removing a
  # checklist can change what every board viewer sees. Note the badge is driven by
  # ITEM counts (items_total.positive?), not by checklist count — so an empty new
  # checklist broadcasts a tile whose badge hasn't appeared yet, and it's the first
  # ITEM that makes it show up (see ChecklistItemsControllerTest).
  #
  # No double render: create appends into checklists_for_<card id>, destroy removes
  # checklist_<id> — both modal-internal, never the tile.
  #
  # There is no #update to cover: it was unreachable (the title is a static <h3>
  # with no rename UI) and its save was unchecked, so it was removed along with
  # its route rather than left as a silent-failure trap.

  def board_stream
    Turbo::StreamsChannel.send(:stream_name_from, @card.list.board)
  end

  def card_target
    ActionView::RecordIdentifier.dom_id(@card)
  end

  test "creating a checklist broadcasts exactly one card replace to the board" do
    broadcasts = capture_broadcasts(board_stream) do
      post card_checklists_url(@card), params: { checklist: { title: "New Checklist" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", card_target]], broadcast_targets(broadcasts)
    # The card still has checklists(:one)'s single incomplete item; the brand new
    # checklist is empty, so the badge total is unchanged at this point.
    assert_match(%r{fa-square-check[^>]*></i>\s*0/1}, broadcast_for(broadcasts, card_target))
  end

  test "destroying the last checklist broadcasts a tile with no progress badge" do
    broadcasts = capture_broadcasts(board_stream) do
      delete card_checklist_url(@card, @checklist), as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", card_target]], broadcast_targets(broadcasts)
    assert_no_match(/fa-square-check/, broadcast_for(broadcasts, card_target),
                    "with its only checklist gone the tile must not render a progress badge")
  end

  test "the actor's own response does not contain the board tile (anti double-render)" do
    post card_checklists_url(@card), params: { checklist: { title: "New Checklist" } }, as: :turbo_stream

    assert_response :success
    assert_no_match(/target="#{card_target}"/, response.body)
  end

  test "should create checklist" do
    assert_difference('Checklist.count') do
      post card_checklists_url(@card), params: { checklist: { title: 'New Checklist' } }
    end
    assert_redirected_to board_url(@card.list.board)
  end

  test "should destroy checklist" do
    assert_difference('Checklist.count', -1) do
      delete card_checklist_url(@card, @checklist)
    end
    assert_redirected_to board_url(@card.list.board)
  end

  # --- validation failure keeps the user in the card modal ---
  #
  # A blank title used to redirect to the board with "Could not add checklist" —
  # out of the modal the user was working in, for a validation error. Reachable
  # from the real UI: the title field is prefilled but carries no `required`.
  #
  # `as: :turbo_stream` does NOT send a turbo-stream request, so the raw Accept
  # header is what exercises the branch the browser actually hits.
  TURBO_STREAM_ONLY = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  test "a blank checklist title conveys the error without redirecting or 500ing" do
    assert_no_difference("Checklist.count") do
      post card_checklists_url(@card), params: { checklist: { title: "" } },
           headers: TURBO_STREAM_ONLY
    end

    # 200, not 422: the form submits from inside the "modal" frame, and Turbo
    # drops a 4xx turbo-stream response for a frame-targeted submission.
    assert_response :success
    assert_match(/turbo-stream/, response.body)
    assert_match(/<turbo-stream action="replace" target="flash"/, response.body)
    assert_match(/can&#39;t be blank|can't be blank/, response.body,
                 "the error must actually reach the user")
  end

  test "a blank checklist title does not broadcast a tile" do
    broadcasts = capture_broadcasts(board_stream) do
      post card_checklists_url(@card), params: { checklist: { title: "" } },
           headers: TURBO_STREAM_ONLY
    end

    assert_empty broadcasts, "a rejected create must not push a tile to other viewers"
  end

  test "a blank checklist title falls back to a redirect carrying the model's error for HTML" do
    assert_no_difference("Checklist.count") do
      post card_checklists_url(@card), params: { checklist: { title: "" } },
           headers: { "Accept" => "text/html" }
    end

    assert_redirected_to board_url(@card.list.board)
    assert_match(/can't be blank/, flash[:alert], "not the old generic copy")
  end

  test "should not create checklist on a card the user has no access to" do
    other_card = cards(:two)

    assert_no_difference('Checklist.count') do
      post card_checklists_url(other_card), params: { checklist: { title: 'Injected' } }
    end
    assert_response :not_found
  end

  test "should not destroy a checklist belonging to a card the user has no access to" do
    other_card = cards(:two)
    other_checklist = checklists(:two)

    assert_no_difference('Checklist.count') do
      delete card_checklist_url(other_card, other_checklist)
    end
    assert_response :not_found
  end

  test "should not destroy a checklist id that belongs to a different card than the one in the path" do
    foreign_checklist = checklists(:two) # belongs to cards(:two)

    assert_no_difference('Checklist.count') do
      delete card_checklist_url(@card, foreign_checklist)
    end
    assert_response :not_found
  end
end
