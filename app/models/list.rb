class List < ApplicationRecord
  belongs_to :board
  has_many :cards, -> { order(position: :asc) }, dependent: :destroy

  validates :name, presence: true

  # "Acts as List" pattern (Simple version):
  # Before creating a new list, assign it to the last position
  before_create :set_position

  private

  def set_position
    # If there are no lists, make this #1. If there are, make this Last + 1.
    last_position = board.lists.maximum(:position) || 0
    self.position = last_position + 1
  end
end
