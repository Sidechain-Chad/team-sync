require "test_helper"

class AttachmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @board = boards(:one)
    @list = lists(:one)
    @card = cards(:one)
    @attachment = fixture_file_upload('test/fixtures/files/test.png', 'image/png')
    @card.attachments.attach(@attachment)
    @active_storage_attachment = @card.attachments.last
  end

  test "should redirect destroy when not logged in" do
    delete card_attachment_url(@card, @active_storage_attachment)
    assert_redirected_to new_user_session_url
  end

  test "should destroy attachment when logged in" do
    sign_in @user
    assert_difference -> { @card.attachments.count }, -1 do
      delete card_attachment_url(@card, @active_storage_attachment)
    end
    assert_redirected_to board_url(@card.list.board)
  end

  test "should create attachment when logged in" do
    sign_in @user
    file = fixture_file_upload("test.png", "image/png")
    assert_difference -> { Activity.count }, 1 do
      post card_attachments_url(@card), params: { file: file }
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert_includes json["url"], "test.png"
    assert_equal "test.png", json["filename"]
  end

  test "should not create attachment with invalid type" do
    sign_in @user
    file = fixture_file_upload("test.png", "application/x-ruby")
    # We rename it in the params to bypass the extension check too
    assert_no_difference -> { Activity.count } do
      post card_attachments_url(@card), params: { file: Rack::Test::UploadedFile.new(file.path, "application/x-ruby", true, original_filename: "test.rb") }
    end
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match "isn't an allowed file type", json["error"]
  end
end
