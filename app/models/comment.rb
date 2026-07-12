class Comment < ApplicationRecord
  belongs_to :card, counter_cache: true
  belongs_to :user, optional: true

  validates :content, presence: true

  # This makes the comment appear instantly on everyone's screen when created
  after_create_commit do
    broadcast_prepend_to card, target: "activities_and_comments", partial: "comments/comment"
  end
end
