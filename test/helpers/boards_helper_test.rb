require "test_helper"

class BoardsHelperTest < ActionView::TestCase
  # See MediaHelperTest — real attaches here need the :test adapter to
  # avoid a background-job pileup under this app's default :async adapter.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "board_tile_url returns nil when the board has no avatar attached" do
    assert_nil board_tile_url(boards(:one))
  end

  test "board_tile_url falls back to the named :tile variant on non-Cloudinary services" do
    board = boards(:one)
    board.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "tile.png", content_type: "image/png"
    )

    assert_match %r{/rails/active_storage/}, board_tile_url(board)
  end

  test "board_tile_url builds a Cloudinary transformation URL when the blob lives on cloudinary" do
    board = boards(:one)
    board.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "tile.png", content_type: "image/png"
    )
    blob = board.avatar.blob
    blob.define_singleton_method(:service_name) { "cloudinary" }
    blob.service.define_singleton_method(:public_id) { |key| key.to_s }

    url = board_tile_url(board)

    assert_match "w_400", url
    assert_match "h_160", url
    assert_match "c_fill", url
    assert_match "f_auto", url
    assert_match "q_auto", url
    assert_match blob.key, url
    # Board tiles are center-fill, not face-gravity — unlike avatars.
    assert_no_match(/g_\w/, url)
  end
end
