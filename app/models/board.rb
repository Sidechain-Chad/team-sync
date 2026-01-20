class Board < ApplicationRecord
  belongs_to :user
  # Dependent: :destroy ensures if you delete a board, the lists don't become "orphans" in the DB
  has_many :lists, -> { order(position: :asc) }, dependent: :destroy
  has_many :board_users, dependent: :destroy
  has_many :members, through: :board_users, source: :user

  has_one_attached :avatar

  validates :name, presence: true
end
