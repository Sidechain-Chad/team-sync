class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :actor,     class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true

  validates :action, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Single delivery seam. Trello never notifies you about your own actions,
  # so a self-notification (recipient == actor) is a no-op.
  def self.deliver(recipient:, actor:, notifiable:, action:)
    return if recipient.nil? || recipient == actor
    create!(recipient: recipient, actor: actor, notifiable: notifiable, action: action)
  end

  after_create_commit do
    # Live per-user delivery. The layout subscribes each signed-in user to
    # their own stream (turbo_stream_from current_user). Update the
    # always-present badge live; the dropdown list is lazy-loaded on open
    # (notifications#index) so we don't broadcast it.
    broadcast_replace_to recipient,
      target: "notifications_badge",
      partial: "notifications/badge",
      locals: { count: recipient.notifications.unread.count }
  end

  def read?
    read_at.present?
  end

  # Where clicking this notification lands, and the human string. Resolve the
  # card from the notifiable (Card for added_to_card, Comment for comment).
  def card
    notifiable.is_a?(Comment) ? notifiable.card : notifiable
  end

  def message
    case action
    when "added_to_card" then "added you to this card"
    when "comment"       then "commented on this card"
    else "sent you a notification"
    end
  end
end
