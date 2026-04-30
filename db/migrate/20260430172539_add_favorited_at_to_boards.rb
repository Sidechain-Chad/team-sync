class AddFavoritedAtToBoards < ActiveRecord::Migration[7.1]
  def change
    add_column :boards, :favorited_at, :datetime
  end
end
