require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # Real avatar/cover attaches in this file trigger Active Storage's
    # analyze/transform jobs via after_commit (Rails' transactional test
    # fixtures fire commit callbacks even though the transaction rolls
    # back). This app's default :async adapter would actually run those
    # jobs in background threads that can't see the not-really-committed
    # row, retrying/blocking — the :test adapter just queues them instead.
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.create!(email: "board_test@example.com", password: "password")
    @board = @user.boards.create!(name: "Test Board")
    sign_in @user
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter
  end

  test "should toggle favorite via patch" do
    assert_difference "BoardFavorite.count", 1 do
      patch toggle_favorite_board_url(@board), as: :turbo_stream
    end
    assert_response :success
    assert @board.favorited_by?(@user)

    assert_difference "BoardFavorite.count", -1 do
      patch toggle_favorite_board_url(@board), as: :turbo_stream
    end
    assert_response :success
    assert_not @board.favorited_by?(@user)
  end

  test "toggle_favorite response replaces the star button, starred section, and sidebar starred list" do
    patch toggle_favorite_board_url(@board), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="replace" targets=".board-star-#{@board.id}"/, response.body)
    assert_match(/turbo-stream action="replace" target="starred_section"/, response.body)
    assert_match(/turbo-stream action="replace" target="starred_sidebar_list"/, response.body)
    assert_match @board.name, response.body
  end

  test "unstarring the last starred board renders the empty starred-section placeholder" do
    patch toggle_favorite_board_url(@board), as: :turbo_stream
    assert @board.reload.favorited_by?(@user)

    patch toggle_favorite_board_url(@board), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="replace" target="starred_section"/, response.body)
    assert_no_match "fa-star text-yellow-400", response.body
  end

  test "a plain GET of the board page never carries the one-shot completion pop, even with completed cards present" do
    list = @board.lists.create!(name: "List", position: 1)
    list.cards.create!(title: "Done already", completed: true)

    get board_url(@board)

    assert_response :success
    assert_no_match(/animate-complete-pop/, response.body)
  end

  test "visiting boards A, B, A yields recents in [A, B] order, most-recent first" do
    board_b = @user.boards.create!(name: "Board B")

    get board_url(@board)
    get board_url(board_b)
    get board_url(@board)

    get boards_url

    assert_response :success
    assert_equal [@board.id, board_b.id], session[:recent_board_ids]
  end

  test "recent boards cap holds at 6 — visiting a 7th drops the oldest" do
    boards = 6.times.map { |i| @user.boards.create!(name: "Extra #{i}") }
    boards.each { |b| get board_url(b) }
    get board_url(@board) # 7th distinct visit, @board pushes out boards.first

    get boards_url

    assert_response :success
    assert_equal 6, session[:recent_board_ids].size
    assert_not_includes session[:recent_board_ids], boards.first.id
    assert_equal @board.id, session[:recent_board_ids].first
  end

  test "a board the user loses access to disappears from recents without erroring" do
    other_owner = User.create!(email: "other_owner@example.com", password: "password")
    shared_board = other_owner.boards.create!(name: "Shared Board")
    shared_board.board_users.create!(user: @user)

    get board_url(shared_board)
    get board_url(@board)

    shared_board.board_users.find_by(user: @user).destroy

    get boards_url

    assert_response :success
    assert_equal [@board.id], session[:recent_board_ids]
  end

  test "board show renders each card with filter data attributes" do
    list = @board.lists.first
    card = list.cards.create!(title: "Filtered card", due_date: 2.days.from_now)
    label = @board.labels.first
    card.labels << label
    member = User.create!(email: "filter_member@example.com", password: "password")
    @board.board_users.create!(user: member)
    card.members << member

    get board_url(@board)

    assert_response :success
    assert_match %r{data-filter-labels="#{label.id}"}, response.body
    assert_match %r{data-filter-members="#{member.id}"}, response.body
    assert_match %r{data-filter-due="upcoming"}, response.body
  end

  test "filter popover renders one checkbox per board label and board member" do
    member = User.create!(email: "filter_member2@example.com", password: "password")
    @board.board_users.create!(user: member)

    get board_url(@board)

    assert_response :success
    # +1 each for the "No labels" / "Unassigned" checkboxes.
    assert_equal @board.labels.count + 1, response.body.scan(/data-category="label"/).size
    assert_equal @board.active_members.count + 1, response.body.scan(/data-category="member"/).size
    assert_equal 5, response.body.scan(/data-category="due"/).size
  end

  test "owner can destroy their board" do
    assert_difference('Board.count', -1) do
      delete board_url(@board)
    end
    assert_redirected_to root_url
  end

  test "a shared member cannot destroy the board" do
    member = User.create!(email: "member@example.com", password: "password")
    @board.board_users.create!(user: member)
    sign_out @user
    sign_in member

    assert_no_difference('Board.count') do
      delete board_url(@board)
    end
    assert_response :not_found
  end

  test "a non-member cannot destroy another user's board" do
    outsider = User.create!(email: "outsider@example.com", password: "password")
    sign_out @user
    sign_in outsider

    assert_no_difference('Board.count') do
      delete board_url(@board)
    end
    assert_response :not_found
  end

  test "edit page hides owner-only member controls from a shared member but still shows the member list" do
    member = User.create!(email: "member@example.com", password: "password")
    @board.board_users.create!(user: member)
    sign_out @user
    sign_in member

    get edit_board_url(@board)

    assert_response :success
    assert_match member.email, response.body
    assert_no_match "Remove", response.body
    assert_no_match "Invite", response.body
  end

  test "edit page shows owner-only member controls to the owner" do
    member = User.create!(email: "member@example.com", password: "password")
    @board.board_users.create!(user: member)

    get edit_board_url(@board)

    assert_response :success
    assert_match "Remove", response.body
    assert_match "Invite", response.body
  end

  test "board render does not synchronously process card cover or board avatar variants" do
    list = @board.lists.first
    card = list.cards.create!(title: "Cover Card")
    card.attachments.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "cover.png", content_type: "image/png"
    )
    @board.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )
    @board.background.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "background.png", content_type: "image/png"
    )

    # Neither variant has been processed yet (no background job ran in this
    # test), so if the view still called .processed inline, this would both
    # be slow and create ActiveStorage::VariantRecord rows here and now.
    assert_no_difference "ActiveStorage::VariantRecord.count" do
      get board_url(@board)
    end

    assert_response :success
    assert_match "/rails/active_storage/", response.body
  end

  test "updating a board with a background upload attaches it" do
    patch board_url(@board), params: {
      board: { background: fixture_file_upload("test.png", "image/png") }
    }

    assert_redirected_to board_url(@board)
    assert @board.reload.background.attached?
  end

  test "removing a board background purges it asynchronously" do
    @board.background.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "background.png", content_type: "image/png"
    )

    assert_enqueued_with job: ActiveStorage::PurgeJob do
      patch board_url(@board), params: { board: { remove_background: "1" } }
    end

    assert_redirected_to board_url(@board)
  end

  test "boards index renders the photo tile for a board with only a background attached (no avatar)" do
    @board.background.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "background.png", content_type: "image/png"
    )

    get boards_url

    assert_response :success
    # _cover.html.erb must branch on board_tile_url's presence, not on
    # board.avatar.attached? directly — else a background-only board (no
    # avatar) silently falls through to the gradient despite having a
    # valid tile URL.
    assert_match "/rails/active_storage/", response.body
  end

  test "switcher renders each board with its own cover gradient, not one shared hardcoded gradient" do
    other_board = @user.boards.create!(name: "Other Board")

    helper = Object.new.extend(BoardsHelper)
    gradient1 = helper.board_cover_gradient_classes(@board)
    gradient2 = helper.board_cover_gradient_classes(other_board)

    assert_not_equal gradient1, gradient2,
      "fixture boards must land in different gradient buckets for this test to prove anything"

    get switch_boards_url

    assert_response :success
    assert_match gradient1, response.body
    assert_match gradient2, response.body
  end

  test "board show query count stays flat as card count grows" do
    # Each size gets its own user + fresh sign-in — reusing one Warden
    # session across two `get`s in a row adds an extra session-revalidation
    # query on the second request that has nothing to do with card count,
    # which would make this test flaky/wrong.
    small = count_queries_for_board_show(cards_per_list: 5)
    large = count_queries_for_board_show(cards_per_list: 10)

    # Ceiling observed after the N+1 fixes (checklist_items eager-loaded
    # alongside checklists, comments read from the comments_count counter
    # cache instead of being loaded): a handful of includes queries plus
    # auth/session lookups. Small buffer over the observed number so an
    # unrelated future addition doesn't make this test flaky for no reason.
    # Bumped 13 -> 14 for the filter popover's board.labels read (a single
    # fixed-cost query, independent of card count — board.user/.members
    # were already loaded for the header avatar row and aren't duplicated).
    # Bumped 14 -> 19 for avatar support: board.user/.members avatar_attachment
    # + blob (preloaded via Preloader in BoardsController#show) plus the
    # BOARD_PAGE_INCLUDES member-chip avatar_attachment + blob preload. All
    # are fixed-cost — one lookup per distinct owner/member regardless of
    # how many cards or lists exist — which the equality assertion below
    # proves by holding flat at 5 vs 10 cards_per_list.
    # Bumped 19 -> 20 for board_background_url's board.background.attached?
    # check in the canvas wallpaper branch — a single fixed-cost lookup on
    # the board's own attachment, once per page load, independent of cards.
    # Bumped 20 -> 21 for the top-nav notifications bell's unread-count
    # query (current_user.notifications.unread.count) — renders on every
    # page, fixed-cost, independent of card count.
    assert_operator small, :<=, 21

    assert_equal small, large, "query count must not grow with card count (N+1 regression)"
  end

  # --- failure branches must not 500 on a turbo-stream-only request ---
  #
  # boards/new and boards/edit exist only as HTML, and `render :new/:edit` looks
  # the template up in the REQUEST's formats — so a turbo-stream-only Accept found
  # nothing and raised MissingTemplate. These are plain full-page forms whose
  # success path is a redirect, so the fix pins the render to HTML and keeps 422
  # (Turbo needs a 4xx to re-render a form).
  TURBO_STREAM_ONLY = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  test "create with a blank name does not raise for a turbo-stream-only request" do
    assert_no_difference "Board.count" do
      post boards_url, params: { board: { name: "" } }, headers: TURBO_STREAM_ONLY
    end

    assert_response :unprocessable_entity
    assert_match(/can&#39;t be blank/, response.body,
                 "the failure must be conveyed as readable text, not just a wrapper class")
  end

  test "create with a blank name re-renders the form with 422 for an HTML request" do
    assert_no_difference "Board.count" do
      post boards_url, params: { board: { name: "" } }, headers: { "Accept" => "text/html" }
    end

    assert_response :unprocessable_entity
    assert_select "form"
    assert_select "p.text-danger-600", text: "can't be blank"
  end

  test "update with a blank name does not raise for a turbo-stream-only request" do
    original = @board.name

    patch board_url(@board), params: { board: { name: "" } }, headers: TURBO_STREAM_ONLY

    assert_response :unprocessable_entity
    assert_equal original, @board.reload.name
  end

  test "update with a blank name re-renders the form with 422 for an HTML request" do
    patch board_url(@board), params: { board: { name: "" } }, headers: { "Accept" => "text/html" }

    assert_response :unprocessable_entity
    assert_select "form"
    assert_select "p.text-danger-600", text: "can't be blank"
  end

  # --- validation messages on the board forms ---
  #
  # Both forms previously conveyed a failed save ONLY through Rails'
  # field_with_errors wrapper, which this app has no CSS for at all — so a blank
  # name produced no visible feedback whatsoever. These assert the message text,
  # deliberately: asserting the wrapper class is what let the gap hide.

  test "create with a blank name shows the error message next to the name field" do
    post boards_url, params: { board: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "p.text-danger-600", text: "can't be blank"
    # The field itself is flagged too, mirroring account/profile.
    assert_select "input#board_name.border-danger-600"
  end

  test "update with a blank name shows the error message next to the name field" do
    patch board_url(@board), params: { board: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "p.text-danger-600", text: "can't be blank"
    assert_select "input#board_name.border-danger-600"
  end

  test "a successful board create renders no error message" do
    post boards_url, params: { board: { name: "Valid Board Name" } }

    assert_redirected_to board_url(Board.find_by!(name: "Valid Board Name"))
  end

  test "the board form shows no error message before submission" do
    get new_board_url

    assert_response :success
    assert_select "p.text-danger-600", false, "a pristine form must not show errors"
  end

  # --- board activity feed ---

  test "activity feed lists activities for cards on this board" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Feed Card")
    Activity.create!(user: @user, card: card, action: "created")

    get activity_board_url(@board)

    assert_response :success
    assert_match "Feed Card", response.body
    assert_match "created this card", response.body
  end

  test "activity feed excludes activities from another board" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    mine = list.cards.create!(title: "Mine Card")
    Activity.create!(user: @user, card: mine, action: "created")

    other_board = @user.boards.create!(name: "Other Board")
    other_list = other_board.lists.create!(name: "Other List", position: 1)
    other_card = other_list.cards.create!(title: "Elsewhere Card")
    Activity.create!(user: @user, card: other_card, action: "created")

    get activity_board_url(@board)

    assert_response :success
    assert_match "Mine Card", response.body
    assert_no_match(/Elsewhere Card/, response.body)
  end

  test "activity feed orders newest first" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    older_card = list.cards.create!(title: "Older Card")
    newer_card = list.cards.create!(title: "Newer Card")
    Activity.create!(user: @user, card: older_card, action: "created", created_at: 2.days.ago)
    Activity.create!(user: @user, card: newer_card, action: "created", created_at: 1.hour.ago)

    get activity_board_url(@board)

    assert_response :success
    assert_operator response.body.index("Newer Card"), :<, response.body.index("Older Card")
  end

  test "activity feed caps at 50 entries" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Feed Card")
    55.times { |i| Activity.create!(user: @user, card: card, action: "renamed", description: "Rename #{i}") }

    get activity_board_url(@board)

    assert_response :success
    assert_equal 50, response.body.scan(/data-activity-row/).size
  end

  test "activity feed shows an empty state when the board has no activity" do
    get activity_board_url(@board)

    assert_response :success
    assert_match "No activity yet.", response.body
  end

  test "activity feed on a board the user has no access to is not found" do
    stranger = User.create!(email: "feed_stranger@example.com", password: "password")
    other_board = stranger.boards.create!(name: "Private Board")

    get activity_board_url(other_board)

    assert_response :not_found
  end

  test "activity feed redirects unauthenticated users" do
    sign_out @user

    get activity_board_url(@board)

    assert_redirected_to new_user_session_url
  end

  test "activity feed query count stays flat as activity count grows" do
    small = count_queries_for_board_activity(activity_count: 5)
    large = count_queries_for_board_activity(activity_count: 10)

    assert_equal small, large, "query count must not grow with activity count (N+1 regression)"
  end

  # --- comments merged into the board activity feed ---

  test "activity feed includes a comment on a card on this board" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Commented Card")
    card.comments.create!(user: @user, content: "A comment worth seeing")

    get activity_board_url(@board)

    assert_response :success
    assert_match "A comment worth seeing", response.body
    assert_match "Commented Card", response.body
    assert_match "commented on", response.body
  end

  test "activity feed excludes a comment on another board's card" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    list.cards.create!(title: "Mine Card").comments.create!(user: @user, content: "Local comment body")

    other_board = @user.boards.create!(name: "Other Board")
    other_list = other_board.lists.create!(name: "Other List", position: 1)
    other_list.cards.create!(title: "Elsewhere Card").comments.create!(user: @user, content: "Foreign comment body")

    get activity_board_url(@board)

    assert_response :success
    assert_match "Local comment body", response.body
    assert_no_match(/Foreign comment body/, response.body)
  end

  test "activity feed interleaves comments and activities strictly newest-first" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Interleaved Card")

    Activity.create!(user: @user, card: card, action: "renamed", description: "OLDEST-ACTIVITY", created_at: 4.hours.ago)
    card.comments.create!(user: @user, content: "MIDDLE-COMMENT", created_at: 3.hours.ago)
    Activity.create!(user: @user, card: card, action: "renamed", description: "NEWER-ACTIVITY", created_at: 2.hours.ago)
    card.comments.create!(user: @user, content: "NEWEST-COMMENT", created_at: 1.hour.ago)

    get activity_board_url(@board)

    assert_response :success
    positions = %w[NEWEST-COMMENT NEWER-ACTIVITY MIDDLE-COMMENT OLDEST-ACTIVITY].map { |m| response.body.index(m) }
    assert_equal positions.compact, positions, "every marker should be present"
    assert_equal positions.sort, positions, "feed must be strictly newest-first across both types"
  end

  test "activity feed caps the merged result at 50 rows, newest first" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Busy Card")

    # 40 of each: the merged newest-50 must be drawn from both sides, which is
    # why each side is fetched 50-deep before merging.
    40.times { |i| Activity.create!(user: @user, card: card, action: "renamed", description: "A#{i}", created_at: (100 - i).minutes.ago) }
    40.times { |i| card.comments.create!(user: @user, content: "C#{i}", created_at: (60 - i).minutes.ago) }

    get activity_board_url(@board)

    assert_response :success
    assert_equal 50, response.body.scan(/data-feed-row/).size

    # The newest 50 of those 80 are: all 40 comments (newest) + the 10 newest
    # activities. So the oldest activities must have fallen off the end.
    assert_match "C39", response.body
    assert_no_match(/\bA0\b/, response.body)
  end

  test "activity feed truncates a long comment body" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Long Comment Card")
    body = "L" * 300
    card.comments.create!(user: @user, content: body)

    get activity_board_url(@board)

    assert_response :success
    assert_no_match(/L{200}/, response.body, "the full 300-char body must not be rendered")
    assert_match(/L{100}/, response.body, "a healthy prefix of the body should still show")
  end

  test "activity feed escapes HTML in a comment body rather than rendering it" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "XSS Card")
    card.comments.create!(user: @user, content: "<script>alert('x')</script><b>bold</b>")

    get activity_board_url(@board)

    assert_response :success
    assert_no_match(%r{<script>alert}, response.body)
    assert_no_match(%r{<b>bold</b>}, response.body)
    assert_match "&lt;script&gt;", response.body
    assert_match "&lt;b&gt;bold&lt;/b&gt;", response.body
  end

  # Regression: an ERB output tag written inside a `<%#` comment in one of the
  # feed partials terminated the comment at its own "%>" and leaked the rest of
  # the comment text onto the page as visible content. Caught in the browser,
  # not by the content assertions above — hence this guard.
  test "activity feed renders no leaked ERB source text" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Leak Check Card")
    Activity.create!(user: @user, card: card, action: "created")
    card.comments.create!(user: @user, content: "Leak check comment")

    get activity_board_url(@board)

    assert_response :success
    feed = response.body[/<h1.*?<\/div>\s*<\/div>\s*<\/div>/m] || response.body
    assert_no_match(/%>/, feed, "raw ERB fragment leaked into the rendered feed")
    assert_no_match(/\blocals:/, feed, "partial documentation leaked into the rendered feed")
  end

  test "activity feed query count stays flat as comment count grows" do
    small = count_queries_for_board_activity(activity_count: 5, comment_count: 5)
    large = count_queries_for_board_activity(activity_count: 5, comment_count: 10)

    assert_equal small, large, "query count must not grow with comment count (N+1 regression)"
  end

  # --- board activity pagination ---
  #
  # Offset/page-based, deliberately NOT a created_at cursor: archive_all_cards
  # writes one Activity per card within the same second, so timestamp ties are
  # routine rather than theoretical, and a `created_at <` cursor would skip or
  # repeat tied rows. A composite (created_at, id) cursor can't work either,
  # because the feed merges two tables with independent id spaces.
  #
  # The risk offset paging carries instead is a non-deterministic sort: if two
  # requests order tied rows differently, page 2 repeats or skips. Hence the
  # tie test below, and the total ordering the controller sorts by.

  test "activity feed page 2 returns the next rows with no overlap and no gaps" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Paged Card")

    # 120 rows alternating type, every one a distinct timestamp so the expected
    # order is unambiguous. Ties get their own test below.
    120.times do |i|
      if i.even?
        Activity.create!(user: @user, card: card, action: "renamed",
                         description: "PA#{i}", created_at: (500 - i).minutes.ago)
      else
        card.comments.create!(user: @user, content: "PC#{i}", created_at: (500 - i).minutes.ago)
      end
    end

    get activity_board_url(@board)
    assert_response :success
    page1 = feed_row_ids
    assert_equal 50, page1.size, "page 1 should be a full page"

    get activity_board_url(@board, page: 2)
    assert_response :success
    page2 = feed_row_ids
    assert_equal 50, page2.size, "page 2 should be a full page"

    assert_empty page1 & page2, "page 2 must not repeat any row from page 1"
    assert_equal 100, (page1 + page2).uniq.size
    # No gaps: the two pages together must be exactly the newest 100 rows, in order.
    assert_equal expected_feed_ids(@board).first(100), page1 + page2
  end

  test "activity feed ordering holds across the page boundary" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Boundary Card")

    120.times do |i|
      if i.even?
        Activity.create!(user: @user, card: card, action: "renamed",
                         description: "BA#{i}", created_at: (500 - i).minutes.ago)
      else
        card.comments.create!(user: @user, content: "BC#{i}", created_at: (500 - i).minutes.ago)
      end
    end

    get activity_board_url(@board)
    last_of_page1 = resolve_feed_row(feed_row_ids.last)

    get activity_board_url(@board, page: 2)
    first_of_page2 = resolve_feed_row(feed_row_ids.first)

    assert_operator last_of_page1.created_at, :>, first_of_page2.created_at,
                    "the last row of page 1 must be newer than the first row of page 2"
  end

  test "activity feed page with tied created_at neither repeats nor skips a row" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Tied Card")

    # The archive_all_cards shape: a burst of rows sharing one timestamp, with
    # the 50-row page boundary landing INSIDE the tied group.
    tied_at = 2.hours.ago.change(usec: 0)
    40.times { |i| Activity.create!(user: @user, card: card, action: "archived", description: "TA#{i}", created_at: tied_at) }
    30.times { |i| card.comments.create!(user: @user, content: "TC#{i}", created_at: tied_at) }

    get activity_board_url(@board)
    page1 = feed_row_ids
    assert_equal 50, page1.size

    get activity_board_url(@board, page: 2)
    page2 = feed_row_ids
    assert_equal 20, page2.size, "the remaining tied rows should all come back"

    assert_empty page1 & page2, "tied rows must not repeat across pages"
    assert_equal 70, (page1 + page2).uniq.size, "every tied row must appear exactly once"
  end

  test "activity feed shows Load more on a full page and hides it on a short final page" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Short Page Card")

    60.times { |i| Activity.create!(user: @user, card: card, action: "renamed", description: "SA#{i}", created_at: (200 - i).minutes.ago) }

    get activity_board_url(@board)
    assert_response :success
    assert_equal 50, feed_row_ids.size
    assert_match(/id="activity_load_more"/, response.body, "a full page should offer Load more")

    get activity_board_url(@board, page: 2)
    assert_response :success
    assert_equal 10, feed_row_ids.size
    assert_no_match(/id="activity_load_more"/, response.body, "a short final page has no more history")
  end

  test "activity feed hides Load more when the whole feed fits on one page" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Tiny Feed Card")
    Activity.create!(user: @user, card: card, action: "renamed", description: "ONLY-ONE")

    get activity_board_url(@board)

    assert_response :success
    assert_no_match(/id="activity_load_more"/, response.body)
  end

  test "activity feed treats a junk or out-of-range page param as page 1" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Junk Page Card")
    60.times { |i| Activity.create!(user: @user, card: card, action: "renamed", description: "JA#{i}", created_at: (200 - i).minutes.ago) }

    get activity_board_url(@board)
    page1 = feed_row_ids

    ["0", "-3", "abc", ""].each do |junk|
      get activity_board_url(@board, page: junk)
      assert_response :success
      assert_equal page1, feed_row_ids, "page=#{junk.inspect} should fall back to page 1"
    end
  end

  test "activity feed page 2 appends into the feed via turbo_stream" do
    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Append Card")
    60.times { |i| Activity.create!(user: @user, card: card, action: "renamed", description: "NA#{i}", created_at: (200 - i).minutes.ago) }

    get activity_board_url(@board, page: 2), as: :turbo_stream

    assert_response :success
    # Appends the rows into the existing container rather than replacing the feed.
    assert_match(/<turbo-stream action="append" target="activity_feed_rows"/, response.body)
    # And updates the Load more control itself — this is the short final page,
    # so the control must be emptied out.
    assert_match(/<turbo-stream action="replace" target="activity_load_more_frame"/, response.body)
    assert_no_match(/id="activity_load_more"/, response.body)
  end

  test "activity pagination does not leak another board's rows" do
    other_board = boards(:two)
    other_list = other_board.lists.create!(name: "Other List", position: 1)
    other_card = other_list.cards.create!(title: "Other Card")
    60.times { |i| Activity.create!(user: users(:two), card: other_card, action: "renamed", description: "FOREIGN#{i}", created_at: (200 - i).minutes.ago) }

    list = @board.lists.create!(name: "Feed List", position: 1)
    card = list.cards.create!(title: "Mine Card")
    60.times { |i| Activity.create!(user: @user, card: card, action: "renamed", description: "MINE#{i}", created_at: (200 - i).minutes.ago) }

    get activity_board_url(@board, page: 2)

    assert_response :success
    assert_no_match(/FOREIGN/, response.body)
  end

  private

  # Row identities as rendered, in document order — "activity_12" / "comment_7".
  # Identity has to carry the type: the feed merges two tables with independent
  # id spaces, so a bare id would collide across them.
  def feed_row_ids
    response.body.scan(/data-feed-row="([^"]+)"/).flatten
  end

  def resolve_feed_row(dom_id)
    type, id = dom_id.split("_")
    type == "activity" ? Activity.find(id) : Comment.find(id)
  end

  # The whole feed for a board, newest first, as row identities. Only meaningful
  # when every row has a distinct created_at — with ties the true order is not
  # determined by timestamp alone, which is the point of the tie test.
  def expected_feed_ids(board)
    card_ids = Card.where(list_id: board.lists.select(:id)).select(:id)
    rows = Activity.where(card_id: card_ids).to_a + Comment.where(card_id: card_ids).to_a
    rows.sort_by(&:created_at).reverse.map { |r| ActionView::RecordIdentifier.dom_id(r) }
  end

  def count_queries_for_board_activity(activity_count:, comment_count: 0)
    # Keyed on BOTH counts — the comment-growth test calls this twice with the
    # same activity_count, and a shared email would collide on uniqueness.
    suffix = "#{activity_count}x#{comment_count}"
    user = User.create!(email: "feedperf#{suffix}@example.com", password: "password")
    attach_test_avatar(user)
    sign_in user

    board = user.boards.create!(name: "Feed Perf Board #{suffix}")
    board.lists.destroy_all
    list = board.lists.create!(name: "List", position: 1)

    # A second actor with their own avatar, so the feed renders more than one
    # distinct user's avatar — proving the per-user avatar preload is fixed
    # cost (one lookup per distinct actor) rather than per activity row.
    other = User.create!(email: "feedperfother#{suffix}@example.com", password: "password")
    attach_test_avatar(other)
    board.board_users.create!(user: other)

    # One card per activity, so a missing `card: :list` include shows up as
    # growth too, not just a missing `:user` include.
    activity_count.times do |i|
      card = list.cards.create!(title: "Card #{i}")
      Activity.create!(user: i.even? ? user : other, card: card, action: "created")
    end

    # One card per comment too, so a missing `card: :list` on the comment side
    # shows up as growth rather than being masked by an already-loaded card.
    comment_count.times do |i|
      card = list.cards.create!(title: "Commented Card #{i}")
      card.comments.create!(user: i.even? ? user : other, content: "Comment #{i}")
    end

    result = count_queries { get activity_board_url(board) }
    assert_response :success
    sign_out user
    result
  end

  def count_queries_for_board_show(cards_per_list:)
    user = User.create!(email: "perf#{cards_per_list}@example.com", password: "password")
    attach_test_avatar(user)
    sign_in user

    board = user.boards.create!(name: "Perf Board #{cards_per_list}")
    board.lists.destroy_all # drop the seeded defaults for a controlled count

    # A second, avatar-attached member — exercises the board header's
    # member-strip avatar AND the BOARD_PAGE_INCLUDES member-chip avatar
    # path, not just the (already-loaded) board owner.
    member = User.create!(email: "perfmember#{cards_per_list}@example.com", password: "password")
    attach_test_avatar(member)
    board.board_users.create!(user: member)

    first_card = nil
    3.times do |i|
      list = board.lists.create!(name: "List #{i}", position: i + 1)
      cards_per_list.times do |j|
        card = list.cards.create!(title: "Card #{i}-#{j}")
        first_card ||= card
        2.times do |k|
          checklist = card.checklists.create!(title: "Checklist #{k}", position: k + 1)
          3.times { |m| checklist.checklist_items.create!(content: "Item #{m}", position: m + 1) }
        end
        2.times { |c| card.comments.create!(content: "Comment #{c}", user: user) }
      end
    end
    # Fixed at one card regardless of cards_per_list — this proves the
    # member-chip avatar preload doesn't scale with card count either.
    CardMember.create!(card: first_card, user: member)

    result = count_queries { get board_url(board) }
    assert_response :success
    sign_out user
    result
  end

  def attach_test_avatar(user)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )
  end
end
