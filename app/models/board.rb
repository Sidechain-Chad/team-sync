class Board < ApplicationRecord
  belongs_to :user
  # Dependent: :destroy ensures if you delete a board, the lists don't become "orphans" in the DB
  has_many :lists, -> { order(position: :asc) }, dependent: :destroy

  has_one_attached :avatar

  validates :name, presence: true
end
