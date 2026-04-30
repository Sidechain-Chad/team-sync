class BoardFavorite < ApplicationRecord
  belongs_to :board
  belongs_to :user

  validates :board_id, uniqueness: { scope: :user_id }
end
