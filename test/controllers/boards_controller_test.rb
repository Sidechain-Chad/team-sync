require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "board_test@example.com", password: "password")
    @board = @user.boards.create!(name: "Test Board")
    sign_in @user
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

    # Neither variant has been processed yet (no background job ran in this
    # test), so if the view still called .processed inline, this would both
    # be slow and create ActiveStorage::VariantRecord rows here and now.
    assert_no_difference "ActiveStorage::VariantRecord.count" do
      get board_url(@board)
    end

    assert_response :success
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
    assert_operator small, :<=, 13

    assert_equal small, large, "query count must not grow with card count (N+1 regression)"
  end

  private

  def count_queries_for_board_show(cards_per_list:)
    user = User.create!(email: "perf#{cards_per_list}@example.com", password: "password")
    sign_in user

    board = user.boards.create!(name: "Perf Board #{cards_per_list}")
    board.lists.destroy_all # drop the seeded defaults for a controlled count

    3.times do |i|
      list = board.lists.create!(name: "List #{i}", position: i + 1)
      cards_per_list.times do |j|
        card = list.cards.create!(title: "Card #{i}-#{j}")
        2.times do |k|
          checklist = card.checklists.create!(title: "Checklist #{k}", position: k + 1)
          3.times { |m| checklist.checklist_items.create!(content: "Item #{m}", position: m + 1) }
        end
        2.times { |c| card.comments.create!(content: "Comment #{c}", user: user) }
      end
    end

    result = count_queries { get board_url(board) }
    assert_response :success
    sign_out user
    result
  end
end
