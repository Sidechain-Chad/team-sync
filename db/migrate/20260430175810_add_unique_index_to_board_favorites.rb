class AddUniqueIndexToBoardFavorites < ActiveRecord::Migration[7.1]
  def change
    add_index :board_favorites, [:user_id, :board_id], unique: true
  end
end
