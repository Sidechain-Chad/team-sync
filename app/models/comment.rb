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

  # Notify @mentioned board members first, then every other current card
  # member with the plain "comment" notification. v1 simplification: only
  # current card *members* (beyond anyone @mentioned) are notified — someone
  # who commented earlier but isn't a member isn't auto-watched the way
  # Trello would be.
  after_create_commit do
    mentioned = mentioned_users
    mentioned.each do |u|
      Notification.deliver(recipient: u, actor: user, notifiable: self, action: "mention")
    end
    # Remaining card members who weren't mentioned still get the plain comment
    # notification. `deliver` already no-ops on self; subtracting `mentioned`
    # prevents a mentioned card-member from getting BOTH.
    (card.members - [user] - mentioned).each do |u|
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
