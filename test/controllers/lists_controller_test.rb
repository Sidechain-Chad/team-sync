require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  setup do
    @user = users(:one)
    @board = boards(:one)
    @list = lists(:one)
    sign_in @user

    # Broadcasting renders partials that can attach/deliver; keep jobs on the
    # :test adapter so nothing runs inline under transactional fixtures.
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "should create list" do
    assert_difference('List.count') do
      post board_lists_url(@board), params: { list: { name: 'New List' } }
    end
    assert_redirected_to board_url(@board)
  end

  test "should not create list on a board the user has no access to" do
    other_board = boards(:two)

    assert_no_difference('List.count') do
      post board_lists_url(other_board), params: { list: { name: 'Injected List' } }
    end

    assert_response :not_found
  end

  test "should move list within its board" do
    list_two = @board.lists.create!(name: "List Two")

    patch move_list_url(list_two), params: { list: { position: 1 } }

    assert_response :success
    assert_equal 1, list_two.reload.position
    assert_equal 2, @list.reload.position
  end

  test "should not move a list belonging to another user's board" do
    other_list = lists(:two)

    patch move_list_url(other_list), params: { list: { position: 1 } }

    assert_response :not_found
  end

  # --- broadcast-list-create: new lists appear live for every board viewer ---

  test "create broadcasts the new list to the board's stream exactly once" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      post board_lists_url(@board), params: { list: { name: "Broadcast List" } }, as: :turbo_stream
    end

    assert_response :success
    new_list = List.find_by!(name: "Broadcast List")
    assert_equal 1, broadcasts.size
    # "new_list_form" is the add-list column, a sibling of the list columns
    # inside #board_lists — inserting before it lands the new list after the
    # existing lists and before the add-list affordance.
    assert_match(/turbo-stream action="before" target="new_list_form"/, broadcasts.first)
    assert_match "id=\"#{ActionView::RecordIdentifier.dom_id(new_list)}\"", broadcasts.first
    assert_match "Broadcast List", broadcasts.first
  end

  # --- archive_all_cards ---

  test "archive_all_cards archives every active card in the list" do
    list = @board.lists.create!(name: "Bulk List")
    a = list.cards.create!(title: "A")
    b = list.cards.create!(title: "B")

    patch archive_all_cards_list_url(list), as: :turbo_stream

    assert a.reload.archived?
    assert b.reload.archived?
    assert_equal 0, list.reload.active_cards.count
  end

  test "archive_all_cards leaves other lists' cards alone" do
    list = @board.lists.create!(name: "Bulk List")
    list.cards.create!(title: "Mine")
    bystander = @board.lists.create!(name: "Bystander List").cards.create!(title: "Theirs")

    patch archive_all_cards_list_url(list), as: :turbo_stream

    assert_not bystander.reload.archived?
  end

  test "archive_all_cards does not touch already-archived cards" do
    list = @board.lists.create!(name: "Bulk List")
    already = list.cards.create!(title: "Already")
    already.archive!
    archived_at = already.reload.archived_at
    active = list.cards.create!(title: "Active")

    patch archive_all_cards_list_url(list), as: :turbo_stream

    assert_equal archived_at.to_i, already.reload.archived_at.to_i, "already-archived card was re-archived"
    assert active.reload.archived?
  end

  test "archive_all_cards logs one archived activity per card" do
    list = @board.lists.create!(name: "Bulk List")
    a = list.cards.create!(title: "A")
    b = list.cards.create!(title: "B")

    assert_difference -> { Activity.where(action: "archived").count }, 2 do
      patch archive_all_cards_list_url(list), as: :turbo_stream
    end

    assert_equal 1, a.activities.where(action: "archived").count
    assert_equal 1, b.activities.where(action: "archived").count
    assert_equal @user, a.activities.find_by(action: "archived").user
  end

  test "archive_all_cards broadcasts a single full list replace, not one remove per card" do
    list = @board.lists.create!(name: "Bulk List")
    3.times { |i| list.cards.create!(title: "C#{i}") }
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      patch archive_all_cards_list_url(list), as: :turbo_stream
    end

    assert_equal 1, broadcasts.size
    assert_match(/turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(list)}"/, broadcasts.first)
    assert_no_match(/action="remove"/, broadcasts.first)
  end

  test "archive_all_cards renders nothing for the list in the actor's own response" do
    list = @board.lists.create!(name: "Bulk List")
    list.cards.create!(title: "C")

    patch archive_all_cards_list_url(list), as: :turbo_stream

    assert_response :no_content
    assert_no_match(/#{ActionView::RecordIdentifier.dom_id(list)}/, response.body)
  end

  test "archive_all_cards on another user's list is not found" do
    other_list = lists(:two)
    card = other_list.cards.create!(title: "Untouchable")

    patch archive_all_cards_list_url(other_list), as: :turbo_stream

    assert_response :not_found
    assert_not card.reload.archived?
  end

  # --- sort ---

  test "sort by due_date orders soonest first with nulls last, and persists" do
    list = @board.lists.create!(name: "Sort List")
    no_due = list.cards.create!(title: "No due")
    late   = list.cards.create!(title: "Late",  due_date: 10.days.from_now)
    soon   = list.cards.create!(title: "Soon",  due_date: 1.day.from_now)

    patch sort_list_url(list), params: { sort: "due_date" }, as: :turbo_stream

    assert_equal %w[Soon Late No\ due], list.reload.active_cards.map(&:title)
    # Persisted, not just ordered in the response — re-read from the DB.
    assert_equal [1, 2, 3], [soon, late, no_due].map { |c| c.reload.position }
  end

  test "sort by title orders A to Z and persists" do
    list = @board.lists.create!(name: "Sort List")
    list.cards.create!(title: "cherry")
    list.cards.create!(title: "Apple")
    list.cards.create!(title: "banana")

    patch sort_list_url(list), params: { sort: "title" }, as: :turbo_stream

    assert_equal %w[Apple banana cherry], list.reload.active_cards.map(&:title)
    assert_equal [1, 2, 3], list.reload.active_cards.map(&:position)
  end

  test "sort by newest orders most-recently-created first and persists" do
    list = @board.lists.create!(name: "Sort List")
    oldest = list.cards.create!(title: "Oldest", created_at: 3.days.ago)
    middle = list.cards.create!(title: "Middle", created_at: 2.days.ago)
    newest = list.cards.create!(title: "Newest", created_at: 1.hour.ago)

    patch sort_list_url(list), params: { sort: "newest" }, as: :turbo_stream

    assert_equal %w[Newest Middle Oldest], list.reload.active_cards.map(&:title)
    assert_equal [1, 2, 3], [newest, middle, oldest].map { |c| c.reload.position }
  end

  test "sort pushes archived cards to the tail so positions stay contiguous" do
    list = @board.lists.create!(name: "Sort List")
    list.cards.create!(title: "B")
    archived = list.cards.create!(title: "A-archived")
    archived.archive!
    list.cards.create!(title: "C")

    patch sort_list_url(list), params: { sort: "title" }, as: :turbo_stream

    assert_equal %w[B C], list.reload.active_cards.map(&:title)
    assert_equal [1, 2], list.reload.active_cards.map(&:position)
    # The archived card keeps a position, but after every active one, so the
    # list's acts_as_list sequence has no duplicates or gaps.
    assert_equal 3, archived.reload.position
    assert_equal [1, 2, 3], list.cards.reload.map(&:position).sort
  end

  test "sort broadcasts a single full list replace and renders nothing for the list" do
    list = @board.lists.create!(name: "Sort List")
    2.times { |i| list.cards.create!(title: "C#{i}") }
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      patch sort_list_url(list), params: { sort: "title" }, as: :turbo_stream
    end

    assert_response :no_content
    assert_equal 1, broadcasts.size
    assert_match(/turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(list)}"/, broadcasts.first)
    assert_no_match(/#{ActionView::RecordIdentifier.dom_id(list)}/, response.body)
  end

  test "sort rejects an unknown sort key without reordering anything" do
    list = @board.lists.create!(name: "Sort List")
    b = list.cards.create!(title: "B")
    a = list.cards.create!(title: "A")

    patch sort_list_url(list), params: { sort: "'; DROP TABLE cards; --" }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal [1, 2], [b, a].map { |c| c.reload.position }
  end

  test "sort on another user's list is not found" do
    other_list = lists(:two)

    patch sort_list_url(other_list), params: { sort: "title" }, as: :turbo_stream

    assert_response :not_found
  end

  # --- card_limit via #update ---

  test "update sets a card limit" do
    patch list_url(@list), params: { list: { card_limit: 5 } }, as: :turbo_stream

    assert_response :success
    assert_equal 5, @list.reload.card_limit
  end

  test "update clears a card limit" do
    @list.update!(card_limit: 5)

    patch list_url(@list), params: { list: { card_limit: "" } }, as: :turbo_stream

    assert_response :success
    assert_nil @list.reload.card_limit
  end

  test "update rejects a non-positive card limit" do
    patch list_url(@list), params: { list: { card_limit: 0 } }, as: :turbo_stream

    # 200 for the turbo_stream branch is deliberate — see #update's comment: the
    # WIP form is frame-targeted, and Turbo drops a 4xx turbo-stream response for
    # a frame-targeted submission, so a 422 here would show the user nothing.
    # The HTML branch still returns 422 (covered below).
    assert_response :success
    assert_nil @list.reload.card_limit
  end

  # --- #update broadcasts: renames and WIP limits are live ---
  #
  # Broadcast target is the list's existing header frame — the same frame the
  # inline rename already replaces in the actor's own response, so this is one
  # mechanism rather than a second targeting scheme. `replace` is by id and
  # idempotent, so the actor receiving both their response and this broadcast
  # can't duplicate anything (unlike append/before).

  test "update broadcasts exactly one header replace when the name changes" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      patch list_url(@list), params: { list: { name: "Renamed Live" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "Renamed Live", @list.reload.name
    assert_equal [["replace", "header_list_#{@list.id}"]], broadcast_targets(broadcasts)
    assert_match(/Renamed Live/, broadcast_for(broadcasts, "header_list_#{@list.id}"))
  end

  test "update broadcasts exactly one header replace when the card limit changes" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      patch list_url(@list), params: { list: { card_limit: 5 } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal 5, @list.reload.card_limit
    assert_equal [["replace", "header_list_#{@list.id}"]], broadcast_targets(broadcasts)
    # The pill rides along inside the header frame, so viewers see the new limit.
    assert_match(/id="list_#{@list.id}_card_count"/, broadcast_for(broadcasts, "header_list_#{@list.id}"))
  end

  test "a failed update broadcasts nothing" do
    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream_name) do
      patch list_url(@list), params: { list: { card_limit: 0 } }, as: :turbo_stream
    end

    # 200, not 422 — frame-targeted turbo_stream error render; see #update.
    assert_response :success
    assert_empty broadcasts, "an invalid update must not broadcast a header"
  end

  # --- failure branches must not 500 on a turbo-stream-only request ---
  #
  # `render :edit` looks up a template in the REQUEST's formats. lists/edit exists
  # only as HTML, so a request whose Accept is turbo-stream ALONE finds nothing and
  # raises MissingTemplate. A normal Turbo form submission sends
  # "text/vnd.turbo-stream.html, text/html, ..." and falls through to the HTML
  # template, which is exactly why this stayed invisible from the UI.
  #
  # NOTE: `as: :turbo_stream` does NOT reproduce it — that still resolves to HTML.
  # The bug needs the bare Accept header, so these tests set it explicitly.
  TURBO_STREAM_ONLY = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  test "update with an invalid card_limit does not raise for a turbo-stream-only request" do
    patch list_url(@list), params: { list: { card_limit: 0 } }, headers: TURBO_STREAM_ONLY

    # 200, not 422: both entry points sit inside the list header frame, and Turbo
    # discards a 4xx turbo-stream response for a frame-targeted submission.
    assert_response :success
    assert_nil @list.reload.card_limit
    assert_match(/turbo-stream/, response.body)
    assert_match(/must be greater than 0/, response.body, "the error must actually reach the user")
  end

  test "update with a blank name does not raise for a turbo-stream-only request" do
    original = @list.name

    patch list_url(@list), params: { list: { name: "" } }, headers: TURBO_STREAM_ONLY

    assert_response :success
    assert_equal original, @list.reload.name
    assert_match(/can&#39;t be blank|can't be blank/, response.body)
  end

  test "a failed turbo-stream update restores the header rather than the rejected value" do
    @list.update!(card_limit: 4)

    patch list_url(@list), params: { list: { card_limit: -3 } }, headers: TURBO_STREAM_ONLY

    assert_response :success
    # The header frame is re-rendered from the DB, so the rejected value is
    # discarded rather than left half-applied on screen.
    assert_match(/target="header_list_#{@list.id}"/, response.body)
    assert_match(/id="list_#{@list.id}_card_count"/, response.body)
    assert_equal 4, @list.reload.card_limit
  end

  test "update with an invalid card_limit still re-renders the form with 422 for an HTML request" do
    patch list_url(@list), params: { list: { card_limit: 0 } }, headers: { "Accept" => "text/html" }

    # HTML form re-render keeps 422 — Turbo needs a 4xx to re-render a form.
    assert_response :unprocessable_entity
    assert_nil @list.reload.card_limit
  end

  # --- header rendering of the WIP limit ---

  test "list header shows no card count when no limit is set" do
    @list.update!(card_limit: nil)

    get board_url(@board)

    assert_response :success
    assert_no_match(/data-card-limit-state/, response.body)
  end

  test "list header shows count over limit in the normal state when at or under the limit" do
    list = @board.lists.create!(name: "Limit List", card_limit: 2)
    2.times { |i| list.cards.create!(title: "C#{i}") }

    get board_url(@board)

    assert_response :success
    assert_match(/data-card-limit-state="ok"/, response.body)
    assert_match(/2\s*\/\s*2/, response.body)
  end

  test "list header shows the over-limit warning state when the limit is exceeded" do
    list = @board.lists.create!(name: "Limit List", card_limit: 2)
    3.times { |i| list.cards.create!(title: "C#{i}") }

    get board_url(@board)

    assert_response :success
    assert_match(/data-card-limit-state="over"/, response.body)
    assert_match(/3\s*\/\s*2/, response.body)
    over_pill = response.body[/<[^>]*data-card-limit-state="over"[^>]*>/]
    assert_match(/danger-600/, over_pill, "over-limit pill must use the danger-600 token")
  end

  test "creating a card past the soft limit still works" do
    list = @board.lists.create!(name: "Limit List", card_limit: 2)
    2.times { |i| list.cards.create!(title: "C#{i}") }

    assert_difference -> { list.cards.count }, 1 do
      post list_cards_url(list), params: { card: { title: "Over the limit" } }, as: :turbo_stream
    end

    assert_response :success
  end

  test "create response resets the form but does not itself render the new list (anti double-render)" do
    post board_lists_url(@board), params: { list: { name: "No Dup List" } }, as: :turbo_stream

    assert_response :success
    new_list = List.find_by!(name: "No Dup List")
    assert_no_match(/id="#{ActionView::RecordIdentifier.dom_id(new_list)}"/, response.body)
    assert_match(/turbo-stream action="replace" target="new_list_form"/, response.body)
    assert_match "Add another list", response.body
  end
end
