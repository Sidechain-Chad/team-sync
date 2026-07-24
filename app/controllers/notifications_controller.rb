class NotificationsController < ApplicationController
  before_action :authenticate_user!

  # Renders the lazy-loaded dropdown feed (see the turbo-frame in
  # shared/_top_nav.html.erb) — fetched only when the bell opens, so this
  # query never runs on a normal page load.
  def index
    @notifications = current_user.notifications.recent.includes(:actor, :notifiable).limit(15)
  end

  # Click-through: mark this one notification read, then land on its card.
  # Deliberately a GET-that-mutates rather than a PATCH + separate link —
  # this is the pragmatic Trello-style "click a notification -> go to the
  # thing", and the mutation (setting read_at) is idempotent and has no
  # meaningful side effect to protect against a stray re-fetch/crawl here
  # (an authenticated, same-user-scoped row flip, not a state change visible
  # to anyone else).
  #
  # The redirect lands on a data-turbo-frame="modal" link (see
  # notifications/_notification.html.erb), so its response only ever
  # replaces the modal frame — the badge in the top nav never sees it.
  # Broadcasting the updated count directly is what actually decrements it.
  def read
    notification = current_user.notifications.find(params[:id])
    if notification.read_at.nil?
      notification.update!(read_at: Time.current)
      Notification.broadcast_badge_for(current_user)
    end
    redirect_to card_path(notification.card)
  end

  def read_all
    current_user.notifications.unread.update_all(read_at: Time.current)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "notifications_badge",
          partial: "notifications/badge",
          locals: { count: 0 }
        )
      end
    end
  end
end
