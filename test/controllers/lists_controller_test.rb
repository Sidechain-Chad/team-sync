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

  test "create response resets the form but does not itself render the new list (anti double-render)" do
    post board_lists_url(@board), params: { list: { name: "No Dup List" } }, as: :turbo_stream

    assert_response :success
    new_list = List.find_by!(name: "No Dup List")
    assert_no_match(/id="#{ActionView::RecordIdentifier.dom_id(new_list)}"/, response.body)
    assert_match(/turbo-stream action="replace" target="new_list_form"/, response.body)
    assert_match "Add another list", response.body
  end
end
