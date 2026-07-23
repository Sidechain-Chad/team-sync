class Comment < ApplicationRecord
  belongs_to :card, counter_cache: true
  belongs_to :user, optional: true

  validates :content, presence: true

  # This makes the comment appear instantly on everyone's screen when created
  after_create_commit do
    broadcast_prepend_to card, target: "activities_and_comments", partial: "comments/comment"
  end

  # Notify every other current card member. v1 simplification: only current
  # card *members* are notified — someone who commented earlier but isn't a
  # member isn't auto-watched the way Trello would be.
  after_create_commit do
    (card.members - [user]).each do |member|
      Notification.deliver(recipient: member, actor: user, notifiable: self, action: "comment")
    end
  end
end
