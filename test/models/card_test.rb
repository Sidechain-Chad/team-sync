require "test_helper"

class CardTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionDispatch::TestProcess::FixtureFile

  # Attaching files can enqueue Active Storage jobs (analysis) — under
  # this app's default :async adapter those can run on a background
  # thread that races transactional fixtures. See CardsControllerTest /
  # NotificationTest for the same gotcha.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

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

  # --- #copy_to ---

  test "copy_to copies description" do
    card = cards(:one)
    card.update!(description: "Original description")

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal "Original description", copy.description
  end

  test "copy_to copies labels and members as new join rows, leaving the source's untouched" do
    card = cards(:one)
    card.labels << labels(:two)
    card.members << users(:two)

    original_card_label_ids = card.card_labels.pluck(:id)
    original_card_member_ids = card.card_members.pluck(:id)

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal card.labels.map(&:id).sort, copy.labels.map(&:id).sort
    assert_equal card.members.map(&:id).sort, copy.members.map(&:id).sort

    # The source's own join rows must be untouched (not moved/stolen) —
    # the copy must own brand new card_labels/card_members rows.
    assert_equal original_card_label_ids.sort, card.reload.card_labels.pluck(:id).sort
    assert_equal original_card_member_ids.sort, card.reload.card_members.pluck(:id).sort
    assert_empty copy.card_labels.pluck(:id) & original_card_label_ids
    assert_empty copy.card_members.pluck(:id) & original_card_member_ids
  end

  test "copy_to copies checklists and items, resetting each item's completed to false" do
    card = cards(:one)
    checklist = checklists(:one)
    checklist.checklist_items.first.update!(completed: true)
    second_item = checklist.checklist_items.create!(content: "Second item", completed: true, position: 2)

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal 1, copy.checklists.count
    copied_checklist = copy.checklists.first
    assert_equal checklist.title, copied_checklist.title
    assert_equal 2, copied_checklist.checklist_items.count
    assert copied_checklist.checklist_items.all? { |item| item.completed == false }
    assert_equal [checklist_items(:one).content, second_item.content].sort,
                 copied_checklist.checklist_items.map(&:content).sort
  end

  test "copy_to does not copy comments or activities" do
    card = cards(:one)
    card.comments.create!(user: users(:one), content: "A comment")
    card.log_activity(users(:one), "renamed", "Something")

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal 0, copy.comments.count
    assert_equal 1, copy.activities.count
    assert_equal "copied", copy.activities.first.action
  end

  test "copy_to resets completed, archived_at, comments_count, and due_reminder_sent_at even when the source's are set" do
    card = cards(:one)
    card.update_column(:completed, true)
    card.update_column(:archived_at, Time.current)
    card.update_column(:comments_count, 5)
    card.update_column(:due_reminder_sent_at, Time.current)

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal false, copy.completed
    assert_nil copy.archived_at
    assert_equal 0, copy.comments_count
    assert_nil copy.due_reminder_sent_at
  end

  test "copy_to copies due_date and location fields" do
    card = cards(:one)
    due = 2.days.from_now
    card.update!(due_date: due, latitude: 40.7128, longitude: -74.0060, location_name: "NYC", location_address: "New York, NY")

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_in_delta due, copy.due_date, 1.second
    assert_equal 40.7128, copy.latitude.to_f
    assert_equal(-74.0060, copy.longitude.to_f)
    assert_equal "NYC", copy.location_name
    assert_equal "New York, NY", copy.location_address
  end

  test "copy_to lands the copy last in the target list" do
    card = cards(:one)
    existing = card.list.cards.create!(title: "Existing bottom card")

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert copy.position > existing.reload.position
  end

  test "copy_to into a different list works" do
    card = cards(:one)
    target = card.list.board.lists.create!(name: "Different List")

    copy = card.copy_to(list: target, title: "Copy", user: users(:one))

    assert_equal target.id, copy.list_id
    assert_not_equal card.list_id, copy.list_id
  end

  test "copy_to into the same list works" do
    card = cards(:one)

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal card.list_id, copy.list_id
  end

  test "copy_to uses the submitted title when present" do
    card = cards(:one)

    copy = card.copy_to(list: card.list, title: "Custom Title", user: users(:one))

    assert_equal "Custom Title", copy.title
  end

  test "copy_to falls back to the source title when the submitted title is blank" do
    card = cards(:one)
    card.update!(title: "Source Title")

    copy = card.copy_to(list: card.list, title: "", user: users(:one))

    assert_equal "Source Title", copy.title
  end

  # --- #copy_to attachments (copy-card-polish) ---

  test "copy_to copies attachments by reusing the existing blobs, not re-uploading" do
    card = cards(:one)
    card.attachments.attach(fixture_file_upload("test.png", "image/png"))

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal card.attachments.count, copy.attachments.count
    assert_equal card.attachments.first.blob_id, copy.attachments.first.blob_id
  end

  test "copy_to's cover_image resolves when the source has an image attachment" do
    card = cards(:one)
    card.attachments.attach(fixture_file_upload("test.png", "image/png"))

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert copy.cover_image.present?
    assert_equal card.cover_image.blob_id, copy.cover_image.blob_id
  end

  test "copy_to works fine for a card with no attachments" do
    card = cards(:one)
    assert_not card.attachments.attached?

    copy = card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_not copy.attachments.attached?
    assert_nil copy.cover_image
  end

  test "copy_to does not modify the source card's attachments" do
    card = cards(:one)
    card.attachments.attach(fixture_file_upload("test.png", "image/png"))
    original_count = card.attachments.count

    card.copy_to(list: card.list, title: "Copy", user: users(:one))

    assert_equal original_count, card.reload.attachments.count
  end

  # --- start_date / due_date range validation ---

  test "start_date on or before due_date is valid" do
    card = cards(:one)
    card.due_date   = 5.days.from_now
    card.start_date = 2.days.from_now
    assert card.valid?

    card.start_date = card.due_date
    assert card.valid?, "same instant should be allowed (start <= due)"
  end

  test "start_date after due_date is rejected and never silently swapped" do
    card = cards(:one)
    card.due_date   = 2.days.from_now
    card.start_date = 5.days.from_now

    assert_not card.valid?
    assert_includes card.errors[:start_date].join, "on or before the due date"

    # The values stay exactly as submitted — no reordering behind the user's back.
    assert_operator card.start_date, :>, card.due_date
  end

  test "start_date alone is allowed" do
    card = cards(:one)
    card.update!(due_date: nil, start_date: 3.days.from_now)
    assert_nil card.reload.due_date
    assert_not_nil card.start_date
  end

  test "due_date alone is allowed" do
    card = cards(:one)
    card.update!(start_date: nil, due_date: 3.days.from_now)
    assert_nil card.reload.start_date
    assert_not_nil card.due_date
  end

  test "both dates nil is allowed" do
    card = cards(:one)
    card.update!(start_date: nil, due_date: nil)
    assert card.reload.valid?
  end

  test "date_range? is true only when both dates are present" do
    card = cards(:one)

    card.assign_attributes(start_date: nil, due_date: nil)
    assert_not card.date_range?

    card.assign_attributes(start_date: 1.day.from_now, due_date: nil)
    assert_not card.date_range?

    card.assign_attributes(start_date: nil, due_date: 1.day.from_now)
    assert_not card.date_range?

    card.assign_attributes(start_date: 1.day.from_now, due_date: 2.days.from_now)
    assert card.date_range?
  end

  test "planner_days covers every day from start to due, inclusive" do
    card = cards(:one)
    card.assign_attributes(start_date: Time.zone.parse("2026-05-04 09:00"), due_date: Time.zone.parse("2026-05-06 17:00"))

    assert_equal [Date.new(2026, 5, 4), Date.new(2026, 5, 5), Date.new(2026, 5, 6)], card.planner_days
  end

  test "planner_days is just the due date when there is no start date" do
    card = cards(:one)
    card.assign_attributes(start_date: nil, due_date: Time.zone.parse("2026-05-06 17:00"))

    assert_equal [Date.new(2026, 5, 6)], card.planner_days
  end

  # --- #copy_to graceful failure ---

  test "copy_to raises RecordInvalid (inside its transaction) when the resulting title is blank" do
    card = cards(:one)
    # update_column bypasses the title-presence validation — simulates a
    # source row already in a bad state, since a real persisted card can
    # never have a blank title through normal means (title.presence would
    # otherwise always fall back to a valid source title).
    card.update_column(:title, "")

    assert_no_difference -> { Card.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        card.copy_to(list: card.list, title: "", user: users(:one))
      end
    end
  end
end
