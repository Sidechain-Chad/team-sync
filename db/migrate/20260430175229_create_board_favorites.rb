class CreateBoardFavorites < ActiveRecord::Migration[7.1]
  def change
    create_table :board_favorites do |t|
      t.references :board, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
