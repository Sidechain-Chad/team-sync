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
  def read
    notification = current_user.notifications.find(params[:id])
    notification.update!(read_at: Time.current) if notification.read_at.nil?
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
