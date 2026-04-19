class Label < ApplicationRecord
  belongs_to :board
  has_many :card_labels, dependent: :destroy
  has_many :cards, through: :card_labels

  # Trello's default palette — used for seeding and the picker UI.
  COLORS = %w[green yellow orange red purple blue sky lime pink black].freeze

  validates :color, presence: true, inclusion: { in: COLORS }
end
