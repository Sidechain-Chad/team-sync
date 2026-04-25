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
    assert_redirected_to card_url(@card)
  end
end
