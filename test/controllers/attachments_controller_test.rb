require "test_helper"

class AttachmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @user = users(:one)
    @board = boards(:one)
    @list = lists(:one)
    @card = cards(:one)
    @attachment = fixture_file_upload('test/fixtures/files/test.png', 'image/png')
    @card.attachments.attach(@attachment)
    @active_storage_attachment = @card.attachments.last

    # Notification.deliver's after_create_commit broadcasts via a Turbo Streams
    # job — see NotificationTest for why this needs the :test adapter under
    # transactional fixtures + the app's default :async adapter.
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  # A member and a WATCHER-who-is-not-a-member, neither of them the actor.
  # Mirrors CardsControllerTest#two_subscribers_on.
  def two_subscribers_on(card)
    member = User.create!(email: "attach-sub-member-#{card.id}@example.com", password: "password")
    watcher = User.create!(email: "attach-sub-watcher-#{card.id}@example.com", password: "password")
    @board.board_users.create!(user: member)
    @board.board_users.create!(user: watcher)
    card.members << member
    CardWatcher.create!(card: card, user: watcher)
    [member, watcher]
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

  test "should not create attachment on a card the user has no access to" do
    sign_in users(:two)
    file = fixture_file_upload("test.png", "image/png")

    post card_attachments_url(@card), params: { file: file }

    assert_response :not_found
  end

  test "should not destroy an attachment on a card the user has no access to" do
    sign_in users(:two)

    assert_no_difference -> { @card.attachments.count } do
      delete card_attachment_url(@card, @active_storage_attachment)
    end
    assert_response :not_found
  end

  # --- copy-card-polish: shared-blob deletion safety ---
  #
  # Card#copy_to reuses the source's existing blobs (attach(blob), not a
  # re-upload) rather than duplicating files. This test is the thing that
  # decides whether that's safe: destroy's purge_later must NOT take the
  # blob (and its Cloudinary/disk file) down with it while another card's
  # attachment still references it. The DB-level foreign key on
  # active_storage_attachments.blob_id is what's actually being exercised —
  # ActiveStorage::Blob#purge rescues ActiveRecord::InvalidForeignKey when
  # another attachment row still points at it.
  test "destroying a copy's attachment does not purge a blob still attached to the original card" do
    sign_in @user
    original_blob = @active_storage_attachment.blob
    copy = @card.copy_to(list: @list, title: "Copy", user: @user)
    copy_attachment = copy.attachments.first

    old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    begin
      perform_enqueued_jobs do
        delete card_attachment_url(copy, copy_attachment)
      end
    ensure
      ActiveJob::Base.queue_adapter = old_adapter
    end

    assert_response :redirect
    assert ActiveStorage::Blob.exists?(original_blob.id),
           "expected the shared blob to survive since the original card still references it"
    assert @card.reload.attachments.first.blob.persisted?
  end

  # --- board-tile broadcast ---
  #
  # A card's cover image is derived from its attachments and renders in
  # cards/_card, and the tile also shows a paperclip badge with
  # card.attachments.size — so BOTH image and non-image attachments change what
  # every viewer of the board sees. CardLabelsController and
  # CardMembersController already broadcast the re-rendered tile for the same
  # reason; these two actions didn't.
  #
  # Scope is the board tile only. Other viewers with the card MODAL open still
  # won't see the attachment list itself change — that needs its own target
  # decision and is out of scope here.

  test "attaching an image broadcasts exactly one card replace to the board" do
    sign_in @user
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream) do
      post card_attachments_url(@card), params: { file: fixture_file_upload("test/fixtures/files/test.png", "image/png") }
    end

    assert_response :success
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
  end

  test "attaching a NON-image also broadcasts, because the tile shows an attachment count" do
    sign_in @user
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream) do
      post card_attachments_url(@card), params: { file: fixture_file_upload("test/fixtures/files/test.txt", "text/plain") }
    end

    assert_response :success
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
    # The cover is unchanged for a non-image (Card#cover_image skips them), but
    # the paperclip badge count is not — hence the broadcast.
    assert_match(/fa-paperclip/, broadcast_for(broadcasts, ActionView::RecordIdentifier.dom_id(@card)))
  end

  test "removing an attachment broadcasts exactly one card replace" do
    sign_in @user
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board)

    broadcasts = capture_broadcasts(stream) do
      delete card_attachment_url(@card, @active_storage_attachment), as: :turbo_stream
    end

    assert_response :success
    assert_equal [["replace", ActionView::RecordIdentifier.dom_id(@card)]], broadcast_targets(broadcasts)
  end

  test "removing the cover image broadcasts a tile that no longer renders a cover" do
    sign_in @user
    stream = Turbo::StreamsChannel.send(:stream_name_from, @board)
    assert @card.reload.cover_image, "setup should leave the card with a cover"

    broadcasts = capture_broadcasts(stream) do
      delete card_attachment_url(@card, @active_storage_attachment), as: :turbo_stream
    end

    body = broadcast_for(broadcasts, ActionView::RecordIdentifier.dom_id(@card))
    # purge_later deletes the attachment row synchronously but leaves the
    # in-memory association cached, so without a reload the broadcast would
    # cheerfully re-render the cover that was just removed.
    assert_no_match(/<img[^>]*class="w-full h-\[100px\]/, body,
                    "the re-rendered tile must not still show the purged cover")
  end

  test "the actor's own response does not contain the board tile (anti double-render)" do
    sign_in @user

    delete card_attachment_url(@card, @active_storage_attachment), as: :turbo_stream

    assert_response :success
    assert_no_match(/target="#{ActionView::RecordIdentifier.dom_id(@card)}"/, response.body)
  end

  # --- `attachment_added` notification (tiptap description-editor inline upload) ---

  test "the tiptap inline upload path notifies subscribers, including a watcher who is not a member" do
    sign_in @user
    member, watcher = two_subscribers_on(@card)
    file = fixture_file_upload("test.png", "image/png")

    assert_difference -> { Notification.where(action: "attachment_added").count }, 2 do
      post card_attachments_url(@card), params: { file: file }
    end

    assert_response :success
    recipients = Notification.where(action: "attachment_added").map(&:recipient)
    assert_equal [member, watcher].sort_by(&:id), recipients.sort_by(&:id)
    assert_not_includes recipients, @user, "the actor is never notified about their own action"
  end

  test "a rejected tiptap upload notifies nobody" do
    sign_in @user
    two_subscribers_on(@card)
    file = fixture_file_upload("test.png", "application/x-ruby")

    assert_no_difference -> { Notification.where(action: "attachment_added").count } do
      post card_attachments_url(@card), params: { file: Rack::Test::UploadedFile.new(file.path, "application/x-ruby", true, original_filename: "test.rb") }
    end

    assert_response :unprocessable_entity
  end

  test "destroying an attachment notifies nobody" do
    sign_in @user
    two_subscribers_on(@card)

    assert_no_difference -> { Notification.count } do
      delete card_attachment_url(@card, @active_storage_attachment), as: :turbo_stream
    end
  end
end
