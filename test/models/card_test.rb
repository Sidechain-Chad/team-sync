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

  # --- due_reminder_pending ---

  test "due_reminder_pending includes a card due within the window with a member" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)

    assert_includes Card.due_reminder_pending, card
  end

  test "due_reminder_pending excludes a completed card" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now, completed: true)

    assert_not_includes Card.due_reminder_pending, card
  end

  test "due_reminder_pending excludes an archived card" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now, archived_at: Time.current)

    assert_not_includes Card.due_reminder_pending, card
  end

  test "due_reminder_pending excludes a card already stamped for its current due date" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    card.update_column(:due_reminder_sent_at, Time.current)

    assert_not_includes Card.due_reminder_pending, card
  end

  test "due_reminder_pending excludes a card due outside the window" do
    card = cards(:one)
    card.update!(due_date: 48.hours.from_now)

    assert_not_includes Card.due_reminder_pending, card
  end

  test "due_reminder_pending excludes a card with no due date" do
    card = cards(:one)
    card.update!(due_date: nil)

    assert_not_includes Card.due_reminder_pending, card
  end

  test "due_reminder_pending excludes a card that is already overdue" do
    card = cards(:one)
    card.update!(due_date: 1.hour.ago)

    assert_not_includes Card.due_reminder_pending, card
  end

  # --- reset-on-due-date-change ---

  test "changing a card's due date clears an existing due_reminder_sent_at" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    card.update_column(:due_reminder_sent_at, Time.current)

    card.update!(due_date: 6.hours.from_now)

    assert_nil card.reload.due_reminder_sent_at
  end

  test "saving a card without changing due_date leaves due_reminder_sent_at intact" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    sent_at = Time.current
    card.update_column(:due_reminder_sent_at, sent_at)

    card.update!(title: "Renamed")

    assert_in_delta sent_at, card.reload.due_reminder_sent_at, 1.second
  end
end
