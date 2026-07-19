require "test_helper"

class CardTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # :cover is intentionally NOT preprocessed (see Card's has_many_attached
  # block) — preprocessing enqueues an ActiveStorage::TransformJob that,
  # on this app's Cloudinary storage, round-trips the original and fails
  # ActiveStorage::IntegrityError (see MediaHelper#media_transform_url,
  # which builds Cloudinary's own transformation URL instead and never
  # needs this job to have run).
  test "attaching a cover-eligible image does not enqueue a preprocessing TransformJob" do
    card = cards(:one)
    file = { io: File.open(Rails.root.join("test/fixtures/files/test.png")), filename: "test.png", content_type: "image/png" }

    assert_no_enqueued_jobs(only: ActiveStorage::TransformJob) do
      card.attachments.attach(file)
    end
  end
end
