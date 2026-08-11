class CreateBoardWatchers < ActiveRecord::Migration[7.1]
  def change
    create_table :board_watchers do |t|
      t.references :board, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    # Mirrors card_watchers: a double-submit or retried request must not be able
    # to leave two rows behind. Enforced at the DB, not only by BoardWatcher's
    # uniqueness validation (which races).
    add_index :board_watchers, [:board_id, :user_id], unique: true
  end
end
