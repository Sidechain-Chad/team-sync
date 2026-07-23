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
    assert_operator small, :<=, 20

    assert_equal small, large, "query count must not grow with card count (N+1 regression)"
  end

  private

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
