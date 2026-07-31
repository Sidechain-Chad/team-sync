class Comment < ApplicationRecord
  belongs_to :card, counter_cache: true
  belongs_to :user, optional: true

  # "comment" and "mention" notifications point at the Comment, not the Card, so
  # the cascade is needed here too — a card destroy reaches these through
  # `has_many :comments, dependent: :destroy`. Polymorphic, so no FK can enforce
  # it; see Card#notifications for the same reasoning.
  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :content, presence: true

  # This makes the comment appear instantly on everyone's screen when created
  after_create_commit do
    broadcast_prepend_to card, target: "activities_and_comments", partial: "comments/comment"
  end

  # Notify @mentioned board members first, then every other of the card's
  # SUBSCRIBERS with the plain "comment" notification. Subscribers, not members:
  # watching a card is how you follow a card you're not on (Card#subscribers is
  # members ∪ watchers, deduped, so being both still yields one notification).
  #
  # Still a v1 simplification in one respect: commenting doesn't auto-watch the
  # way Trello does, so an earlier commenter who never watched or joined stays
  # silent.
  after_create_commit do
    mentioned = mentioned_users
    mentioned.each do |u|
      Notification.deliver(recipient: u, actor: user, notifiable: self, action: "mention")
    end
    # Remaining subscribers who weren't mentioned still get the plain comment
    # notification. `deliver` already no-ops on self; subtracting `mentioned`
    # prevents a mentioned subscriber from getting BOTH. A watcher's comment
    # notification is gated by their own `comment` preference inside `deliver`,
    # which is why watching needs no Notification::PREFERENCE_TYPES entry of its
    # own — it widens an audience, it isn't an event type.
    (card.subscribers - [user] - mentioned).each do |u|
      Notification.deliver(recipient: u, actor: user, notifiable: self, action: "comment")
    end
  end

  # Board members explicitly @mentioned in the body, minus the author. Scoped
  # to the board's active members (Trello only lets you mention people on the
  # board), and a mention notifies them even if they aren't a card member —
  # that's the point of @mention (pulling someone in).
  def mentioned_users
    candidates = card.list.board.active_members
    candidates.select { |u| body_mentions?(u) } - [user]
  end

  private

  # Case-insensitive match — a mention is hand-typed, and requiring exact
  # case would silently drop notifications over a capitalization slip.
  # Bounded on both sides: the trailing negative word-character lookahead
  # means "@Jo" doesn't match member "John" and "@John" doesn't match
  # "Johnny"; the leading negative word-character lookbehind means the "@"
  # must start a word, so an email address like john@Bob.com doesn't
  # phantom-mention a member named "Bob". Known v1 limitation: two board
  # members sharing a display_name are ambiguous and would both match —
  # acceptable without a real username field.
  def body_mentions?(user)
    content.to_s.match?(/(?<![[:word:]])@#{Regexp.escape(user.display_name)}(?![[:word:]])/i)
  end
end
