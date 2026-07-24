class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :actor,     class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true

  validates :action, presence: true

  # action => { title:, description: } for the settings toggles. Only types with
  # a live trigger appear here; add a row when a new trigger ships.
  PREFERENCE_TYPES = {
    "comment"       => { title: "Comments",        description: "New comments on cards you're a member of" },
    "mention"       => { title: "Mentions",        description: "When someone @mentions you in a comment" },
    "added_to_card" => { title: "Added to a card", description: "When someone adds you to a card" }
  }.freeze

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Single delivery seam. Trello never notifies you about your own actions,
  # so a self-notification (recipient == actor) is a no-op.
  def self.deliver(recipient:, actor:, notifiable:, action:)
    return if recipient.nil? || recipient == actor
    return unless recipient.notifies?(action)
    create!(recipient: recipient, actor: actor, notifiable: notifiable, action: action)
  end

  after_create_commit { self.class.broadcast_badge_for(recipient) }

  # Live per-user delivery. The layout subscribes each signed-in user to
  # their own stream (turbo_stream_from current_user). Update the
  # always-present badge live; the dropdown list is lazy-loaded on open
  # (notifications#index) so we don't broadcast it.
  #
  # Also called directly from NotificationsController#read: that click-
  # through link targets data-turbo-frame="modal" (same as every other
  # card-open link), so its response only ever replaces the modal frame —
  # the badge, living outside that frame in the top nav, never sees it.
  # Re-broadcasting here is the same fix already used elsewhere in this app
  # for a modal-scoped response needing to update something outside the
  # frame (see CardsController#toggle_complete's per-member cards-row
  # broadcast).
  def self.broadcast_badge_for(user)
    Turbo::StreamsChannel.broadcast_replace_to user,
      target: "notifications_badge",
      partial: "notifications/badge",
      locals: { count: user.notifications.unread.count }
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
    when "mention"       then "mentioned you in a comment"
    else "sent you a notification"
    end
  end
end
