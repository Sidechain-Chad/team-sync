require "test_helper"

class CardTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "attaching a cover-eligible image enqueues a preprocessing TransformJob" do
    card = cards(:one)
    file = { io: File.open(Rails.root.join("test/fixtures/files/test.png")), filename: "test.png", content_type: "image/png" }

    assert_enqueued_with(job: ActiveStorage::TransformJob) do
      card.attachments.attach(file)
    end
  end
end
