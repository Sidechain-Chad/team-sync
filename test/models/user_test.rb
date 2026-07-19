require "test_helper"

class UserTest < ActiveSupport::TestCase
  # Real avatar attaches below trigger Active Storage's analyze/transform
  # jobs via after_commit (Rails' transactional test fixtures fire commit
  # callbacks even though the transaction rolls back). This app's default
  # :async adapter would actually run those jobs in background threads
  # that can't see the not-really-committed row, retrying/blocking — the
  # :test adapter just queues them instead.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "deactivate! sets deactivated_at and clears memberships" do
    user = users(:one)
    board = boards(:one)
    card = cards(:one)
    
    # Ensure they are members
    BoardUser.find_or_create_by!(board: board, user: user)
    CardMember.find_or_create_by!(card: card, user: user)
    
    assert_nil user.deactivated_at
    assert_not_empty user.board_users
    assert_not_empty user.card_members
    
    user.deactivate!
    
    assert_not_nil user.deactivated_at
    assert_empty user.board_users
    assert_empty user.card_members
  end

  test "active_for_authentication? returns false when deactivated" do
    user = users(:one)
    assert user.active_for_authentication?
    
    user.deactivate!
    assert_not user.active_for_authentication?
  end
  
  test "display_name includes deactivated marker" do
    user = users(:one)
    name = user.name
    assert_equal name, user.display_name

    user.deactivate!
    assert_equal "#{name} (deactivated)", user.display_name
  end

  test "accepts a valid png/jpeg/webp avatar under 5 MB" do
    user = users(:one)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )

    assert user.valid?
    assert user.avatar.attached?
  end

  test "rejects a non-image content type" do
    user = users(:one)
    # Genuinely non-image bytes, not just a relabeled image — the
    # validation checks Active Storage's sniffed blob.content_type.
    user.avatar.attach(
      io: StringIO.new("just plain text, not an image"),
      filename: "avatar.txt", content_type: "text/plain"
    )

    assert_not user.valid?
    assert_match "must be a PNG, JPEG, or WebP", user.errors[:avatar].join
  end

  test "rejects an avatar over 5 MB" do
    user = users(:one)
    user.avatar.attach(
      io: StringIO.new("a" * 6.megabytes),
      filename: "avatar.png", content_type: "image/png"
    )

    assert_not user.valid?
    assert_match "must be smaller than 5 MB", user.errors[:avatar].join
  end

  test "avatar validation does not run on saves that don't touch the avatar" do
    user = users(:one)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )
    user.save!

    # A later, unrelated save (e.g. deactivate!) must not re-run the
    # avatar validation against the already-valid, already-attached file.
    assert_nothing_raised { user.deactivate! }
    assert user.reload.avatar.attached?
  end

  test "avatar upload does not require the profile_update save context" do
    demo = User.create!(email: "nameless@example.com", password: "password")
    assert_nil demo[:name]

    demo.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )

    assert demo.save, demo.errors.full_messages.to_s
  end
end
