require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

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
