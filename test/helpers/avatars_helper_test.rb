require "test_helper"

class AvatarsHelperTest < ActionView::TestCase
  # See MediaHelperTest — real attaches here need the :test adapter to
  # avoid a background-job pileup under this app's default :async adapter.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "avatar_image_url returns nil when nothing is attached" do
    assert_nil avatar_image_url(users(:one))
  end

  test "avatar_image_url falls back to the named Active Storage variant on non-Cloudinary services" do
    user = users(:one)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )

    assert_equal "test", user.avatar.blob.service_name
    assert_match %r{/rails/active_storage/}, avatar_image_url(user, variant: :chip)
  end

  test "avatar_image_url builds a Cloudinary transformation URL when the blob lives on cloudinary" do
    user = users(:one)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )
    blob = user.avatar.blob
    # Simulate a Cloudinary-backed blob without a real service instance or
    # network call — this only exercises URL construction.
    blob.define_singleton_method(:service_name) { "cloudinary" }
    blob.service.define_singleton_method(:public_id) { |key| key.to_s }

    url = avatar_image_url(user, variant: :thumb)

    assert_match "w_160", url
    assert_match "h_160", url
    assert_match "c_fill", url
    assert_match "g_face", url
    assert_match "f_auto", url
    assert_match "q_auto", url
    assert_match blob.key, url
  end

  test "avatar_image_url sizes the chip variant at 64px on cloudinary" do
    user = users(:one)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )
    blob = user.avatar.blob
    blob.define_singleton_method(:service_name) { "cloudinary" }
    blob.service.define_singleton_method(:public_id) { |key| key.to_s }

    url = avatar_image_url(user, variant: :chip)

    assert_match "w_64", url
    assert_match "h_64", url
  end
end
