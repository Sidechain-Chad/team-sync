require "test_helper"

class CardsHelperTest < ActionView::TestCase
  # See MediaHelperTest — real attaches here need the :test adapter to
  # avoid a background-job pileup under this app's default :async adapter.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "card_cover_url returns nil when the card has no image attachment" do
    assert_nil card_cover_url(cards(:one))
  end

  test "card_cover_url falls back to the named :cover variant on non-Cloudinary services" do
    card = cards(:one)
    card.attachments.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "cover.png", content_type: "image/png"
    )

    assert_match %r{/rails/active_storage/}, card_cover_url(card)
  end

  test "card_cover_url builds a Cloudinary transformation URL when the blob lives on cloudinary" do
    card = cards(:one)
    card.attachments.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "cover.png", content_type: "image/png"
    )
    blob = card.cover_image.blob
    blob.define_singleton_method(:service_name) { "cloudinary" }
    blob.service.define_singleton_method(:public_id) { |key| key.to_s }

    url = card_cover_url(card)

    assert_match "w_560", url
    assert_match "h_200", url
    assert_match "c_fill", url
    assert_match "f_auto", url
    assert_match "q_auto", url
    assert_match blob.key, url
    # Card covers are center-fill, not face-gravity — unlike avatars.
    assert_no_match(/g_\w/, url)
  end
end
