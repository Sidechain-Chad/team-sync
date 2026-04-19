class Comment < ApplicationRecord
  belongs_to :card
  belongs_to :user

  validates :content, presence: true

  # This makes the comment appear instantly on everyone's screen when created
  after_create_commit do
    broadcast_prepend_to card, target: "comments_list", partial: "comments/comment"
  end
end
