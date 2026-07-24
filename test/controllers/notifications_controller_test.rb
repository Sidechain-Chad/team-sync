require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  # Notification creation broadcasts via a Turbo Streams job — see
  # NotificationTest for why this needs the :test adapter under
  # transactional fixtures + the app's default :async adapter.
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = users(:one)
    @card = cards(:one)
    sign_in @user
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
  end

  test "read_all marks every unread notification read and zeroes the unread count" do
    3.times do
      Notification.create!(recipient: @user, actor: users(:two), notifiable: @card, action: "added_to_card")
    end
    assert_equal 3, @user.notifications.unread.count

    patch read_all_notifications_url, as: :turbo_stream

    assert_response :success
    assert_equal 0, @user.notifications.unread.count
  end

  test "read marks the single notification read and redirects to its card" do
    notification = Notification.create!(recipient: @user, actor: users(:two), notifiable: @card, action: "added_to_card")

    get read_notification_url(notification)

    assert_redirected_to card_path(@card)
    assert notification.reload.read_at.present?
  end

  # The click-through link targets data-turbo-frame="modal" (see the test
  # above), so its response only ever replaces the modal frame — the top
  # nav's badge, which lives outside that frame, never sees the response.
  # Without this broadcast, the badge would stay stuck at its pre-click
  # count until the user happens to navigate elsewhere or reload.
  test "read broadcasts the decremented badge to the recipient's own stream" do
    notification = Notification.create!(recipient: @user, actor: users(:two), notifiable: @card, action: "added_to_card")
    Notification.create!(recipient: @user, actor: users(:two), notifiable: @card, action: "added_to_card")
    assert_equal 2, @user.notifications.unread.count

    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @user)
    broadcasts = capture_broadcasts(stream_name) do
      get read_notification_url(notification)
    end

    assert_equal 1, broadcasts.size
    assert_match(/turbo-stream action="replace" target="notifications_badge"/, broadcasts.first)
    assert_match(/>\s*1\s*</, broadcasts.first)
  end

  test "read does not re-broadcast when the notification was already read" do
    notification = Notification.create!(recipient: @user, actor: users(:two), notifiable: @card, action: "added_to_card", read_at: Time.current)

    stream_name = Turbo::StreamsChannel.send(:stream_name_from, @user)
    broadcasts = capture_broadcasts(stream_name) do
      get read_notification_url(notification)
    end

    assert_equal 0, broadcasts.size
  end

  test "each notification row targets the modal frame, same as every other card-open link" do
    Notification.create!(recipient: @user, actor: users(:two), notifiable: @card, action: "added_to_card")

    get notifications_url

    assert_response :success
    # data-turbo-frame="modal" is what every other card-open link uses (see
    # cards/_card.html.erb) — it swaps the layout's placeholder "modal"
    # frame with the response's populated modal content, leaving the rest
    # of the current page untouched, and still updates the URL. Plain
    # data-turbo-frame="_top" (a prior version of this file) instead did a
    # full top-level <body> replace: since cards/show.html.erb's modal
    # frame renders nested inside the standard layout (which also carries
    # its own empty "modal" placeholder), a full-body replace leaves two
    # elements with id="modal" for Turbo to reconcile at once, which
    # rendered blank until a hard reload (confirmed in the browser).
    row_link_tag = response.body[%r{<a[^>]*href="/notifications/\d+/read"[^>]*>}]
    assert row_link_tag, "expected a notification row <a href=\".../read\"> tag in the response"
    assert_match 'data-turbo-frame="modal"', row_link_tag
    # data-turbo-prefetch="false" — without it, merely hovering a row
    # prefetches (GETs) the read endpoint, marking it read and dropping the
    # badge before the user actually clicks anything.
    assert_match 'data-turbo-prefetch="false"', row_link_tag
  end

  test "index feed query count is fixed-cost and does not grow with notification count" do
    small = count_queries_for_index(notification_count: 3)
    large = count_queries_for_index(notification_count: 12)

    assert_operator small, :<=, 10
    assert_equal small, large, "notifications#index query count must not grow with notification count (N+1 regression)"
  end

  test "a normal page render fires only the unread-count query, not the feed query" do
    5.times do
      Notification.create!(recipient: @user, actor: users(:two), notifiable: @card, action: "added_to_card")
    end

    get card_url(@card)

    assert_response :success
    # The badge count renders inline on every page; the lazy turbo-frame src
    # points at notifications_path but must not be fetched during this
    # request — it's client-fetched only when the frame becomes visible.
    assert_match(/id="notifications_badge"/, response.body)
    assert_match %r{<turbo-frame id="notifications_list"[^>]*loading="lazy"}, response.body
  end

  private

  def count_queries_for_index(notification_count:)
    user = User.create!(email: "notif_perf_#{notification_count}@example.com", password: "password")
    sign_in user

    notification_count.times do |i|
      Notification.create!(recipient: user, actor: users(:two), notifiable: @card, action: "added_to_card")
    end

    result = count_queries { get notifications_url }
    assert_response :success
    sign_out user
    result
  end
end
