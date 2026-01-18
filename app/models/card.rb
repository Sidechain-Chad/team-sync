class Card < ApplicationRecord
  belongs_to :list

  # 1. Scope: This ensures that if I move a card to position 1,
  #    it only affects cards in the SAME list, not every card in the database.
  acts_as_list scope: :list

  validates :title, presence: true
end
