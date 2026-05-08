require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board_one = boards(:one)
    @list_one = lists(:one)
    @list_two = lists(:two)
    @card = cards(:one)
    sign_in @user
  end

  test "should update card and log move activity when list changes" do
    assert_difference -> { Activity.count }, 1 do
      patch card_url(@card), params: { card: { list_id: @list_two.id } }
    end

    assert_redirected_to board_url(@list_two.board)
    @card.reload
    assert_equal @list_two.id, @card.list_id
    
    activity = Activity.last
    assert_equal "moved", activity.action
    assert_equal "#{@list_one.name} to #{@list_two.name}", activity.description
    assert_equal "moved this card from #{@list_one.name} to #{@list_two.name}", activity.message
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
end
