class Card < ApplicationRecord
  belongs_to :list
  belongs_to :assignee, class_name: 'User', optional: true

  # NEW: Allow multiple members
  has_many :card_members, dependent: :destroy
  has_many :members, through: :card_members, source: :user

  # 1. Scope: This ensures that if I move a card to position 1,
  #    it only affects cards in the SAME list, not every card in the database.
  acts_as_list scope: :list

  validates :title, presence: true

  def to_param
    "#{id}-#{title.parameterize}"
  end
end
