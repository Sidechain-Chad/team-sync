class AddIndexToBoardFavoritesUserCreatedAt < ActiveRecord::Migration[7.1]
  def change
    # Composite index that mirrors the boards#index sort pattern:
    # filter by user_id, then sort by created_at. Lets Postgres satisfy
    # both the join filter AND the order clause from a single index scan.
    add_index :board_favorites, [:user_id, :created_at]
  end
end
