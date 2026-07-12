class Label < ApplicationRecord
  belongs_to :board
  # CardLabel is a bare join row (no callbacks, no dependents of its own),
  # so a bulk DELETE is safe and avoids one query per row on label destroy.
  has_many :card_labels, dependent: :delete_all
  has_many :cards, through: :card_labels

  # Trello's default palette — used for seeding and the picker UI.
  COLORS = %w[green yellow orange red purple blue sky lime pink black].freeze

  validates :color, presence: true, inclusion: { in: COLORS }
end
