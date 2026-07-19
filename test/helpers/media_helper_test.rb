require "test_helper"

class MediaHelperTest < ActionView::TestCase
  # Real attaches below trigger Active Storage's analyze/transform jobs via
  # after_commit (Rails' transactional test fixtures fire commit callbacks
  # even though the transaction rolls back). This app's default :async
  # adapter would actually run those jobs in background threads that
  # can't see the not-really-committed row, retrying/blocking — the :test
  # adapter just queues them instead. See profile-avatar branch history.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "media_transform_url returns nil for a nil attachable" do
    assert_nil media_transform_url(nil, variant: :cover, width: 560, height: 200)
  end

  test "media_transform_url falls back to the named Active Storage variant on non-Cloudinary services" do
    card = cards(:one)
    card.attachments.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "cover.png", content_type: "image/png"
    )
    image = card.cover_image

    assert_equal "test", image.blob.service_name
    assert_match %r{/rails/active_storage/}, media_transform_url(image, variant: :cover, width: 560, height: 200)
  end

  test "media_transform_url builds a center-fill Cloudinary URL with no gravity by default" do
    card = cards(:one)
    card.attachments.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "cover.png", content_type: "image/png"
    )
    image = card.cover_image
    blob = image.blob
    blob.define_singleton_method(:service_name) { "cloudinary" }
    blob.service.define_singleton_method(:public_id) { |key| key.to_s }

    url = media_transform_url(image, variant: :cover, width: 560, height: 200)

    assert_match "w_560", url
    assert_match "h_200", url
    assert_match "c_fill", url
    assert_match "f_auto", url
    assert_match "q_auto", url
    assert_match blob.key, url
    assert_no_match "g_face", url
    assert_no_match(/g_\w/, url)
  end

  test "media_transform_url includes gravity only when the caller passes it" do
    card = cards(:one)
    card.attachments.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "cover.png", content_type: "image/png"
    )
    image = card.cover_image
    blob = image.blob
    blob.define_singleton_method(:service_name) { "cloudinary" }
    blob.service.define_singleton_method(:public_id) { |key| key.to_s }

    url = media_transform_url(image, variant: :cover, width: 64, height: 64, gravity: :face)

    assert_match "g_face", url
  end
end
