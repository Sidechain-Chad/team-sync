require "test_helper"

class DueSoonScanJobTest < ActiveSupport::TestCase
  # after_create_commit on Notification broadcasts via a Turbo job — the
  # :async adapter can't see the not-really-committed row under transactional
  # fixtures, so switch to :test for the cases that actually create one.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "creates one due_soon notification per member of an eligible card and stamps due_reminder_sent_at" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    member = users(:one) # already a card member via card_members fixture :one

    assert_difference "Notification.count", 1 do
      DueSoonScanJob.perform_now
    end

    notification = Notification.last
    assert_equal member, notification.recipient
    assert_nil notification.actor
    assert_equal "due_soon", notification.action
    assert_equal card, notification.notifiable

    assert_not_nil card.reload.due_reminder_sent_at
  end

  test "a second run does not re-notify (idempotency)" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)

    DueSoonScanJob.perform_now
    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end

  # Reminders key off due_date ONLY — a start date must not change who gets
  # reminded or when, no matter where it sits relative to the window.
  test "a start date does not change due-soon eligibility" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now, start_date: 5.days.ago)

    assert_difference "Notification.count", 1 do
      DueSoonScanJob.perform_now
    end
    assert_not_nil card.reload.due_reminder_sent_at
  end

  test "a start date inside the reminder window does not make an out-of-window card eligible" do
    card = cards(:one)
    # Due well beyond the 24h window, but starting right now.
    card.update!(due_date: 10.days.from_now, start_date: Time.current)

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
    assert_nil card.reload.due_reminder_sent_at
  end

  test "a start-date-only card is never due-soon eligible" do
    card = cards(:one)
    card.update!(due_date: nil, start_date: 1.hour.from_now)

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end

  test "does not notify a member who has turned due_soon off" do
    card = cards(:one)
    card.update!(due_date: 12.hours.from_now)
    member = users(:one)
    member.update!(notification_preferences: { "due_soon" => false })

    assert_no_difference "Notification.count" do
      DueSoonScanJob.perform_now
    end
  end
end
