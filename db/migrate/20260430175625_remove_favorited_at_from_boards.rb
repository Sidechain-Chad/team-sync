class RemoveFavoritedAtFromBoards < ActiveRecord::Migration[7.1]
  def change
    remove_column :boards, :favorited_at, :datetime
  end
end
