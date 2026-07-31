class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :actor,     class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true

  validates :action, presence: true

  # action => { title:, description: } for the settings toggles. Only types with
  # a live trigger appear here; add a row when a new trigger ships.
  # EVERY action passed to .deliver must appear here. #notifies? is
  # `notification_preferences.fetch(action.to_s, true)`, so an action MISSING from
  # this hash is delivered unconditionally — it silently bypasses the user's
  # preferences instead of failing loudly. NotificationCoverageTest pins that:
  # it greps every deliver call site and fails on an action with no entry here.
  PREFERENCE_TYPES = {
    "comment"           => { title: "Comments",                   description: "New comments on cards you're a member of" },
    "mention"           => { title: "Mentions",                   description: "When someone @mentions you in a comment" },
    "added_to_card"     => { title: "Added to a card",            description: "When someone adds you to a card" },
    "removed_from_card" => { title: "You're removed from a card", description: "Someone removes you as a member from a card" },
    "due_soon"          => { title: "Due dates",                  description: "When a card you're on is coming due" },
    "moved"             => { title: "Cards moved",                description: "Cards you're watching are moved between lists" },
    "archived"          => { title: "Cards archived",             description: "Cards you're watching are archived" }
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
  #
  # Returns nil for an orphan — a notification whose notifiable row is gone.
  # Card and Comment both cascade (`has_many :notifications, as: :notifiable`),
  # so that shouldn't happen going forward, but notifiable is polymorphic and
  # therefore un-FK-able: a raw SQL delete, a pre-cascade destroy, or a restored
  # backup can all still leave one behind. Callers must handle nil — see
  # #orphaned? and notifications/_notification.
  def card
    notifiable.is_a?(Comment) ? notifiable.card : notifiable
  end

  # True when the thing this notification is about no longer exists, so there's
  # nothing to name and nowhere to click through to. The feed skips these rather
  # than raising on nil (the bell dropdown used to 500 for the whole user over a
  # single orphaned row — and an actor-less due_soon is the reachable case, since
  # the partial only falls back to the card title when there's no actor).
  def orphaned?
    card.nil?
  end

  # DELIBERATELY GENERIC for "moved": "moved this card to X" is not possible here
  # without lying. This method is computed from live associations at render time,
  # so it would name the card's CURRENT list, not the list it moved to when the
  # notification was created — actively wrong the moment the card moves again.
  # (Activity gets away with "moved this card from A to B" because it stores the
  # names in its `description` column at write time.) Naming the destination would
  # need a per-notification context column; that's a separate change.
  def message
    case action
    when "added_to_card"     then "added you to this card"
    when "removed_from_card" then "removed you from this card"
    when "comment"           then "commented on this card"
    when "mention"           then "mentioned you in a comment"
    when "due_soon"          then "is due soon"
    when "moved"             then "moved this card"
    when "archived"          then "archived this card"
    else "sent you a notification"
    end
  end
end
