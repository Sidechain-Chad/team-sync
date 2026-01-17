class List < ApplicationRecord
  belongs_to :board
  # Dependent and destroy will delete the card from the db
  has_many :card, -> { order(position: :asc) }, dependent: :destroy

  validates :name, presence: true

  # Before creating a new list, assign it to the last position
  before_create :set_position

  private
  def set_position
    # If there are no lists, make this #1. If there are, make this Last + 1.
    last_position = board.lists.maximum(:position) || 0
    self.position = last_position
  end
end
