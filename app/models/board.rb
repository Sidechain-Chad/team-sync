class Board < ApplicationRecord
  belongs_to :user
  # Dependent and destroy will delete the card from the db
  has_many :lists, -> { order(position: :asc) }, dependent: :destroy

  validates :name, presence: true
end
