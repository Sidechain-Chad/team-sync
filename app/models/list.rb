class List < ApplicationRecord
  belongs_to :board
  has_many :cards, -> { order(position: :asc) }, dependent: :destroy

  validates :name, presence: true

  # Scope ordering to a single board so insert_at / position shifts
  # only affect lists on the same board, not every list in the DB.
  acts_as_list scope: :board
end
