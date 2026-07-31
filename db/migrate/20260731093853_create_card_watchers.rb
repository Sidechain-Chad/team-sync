class CreateCardWatchers < ActiveRecord::Migration[7.1]
  def change
    create_table :card_watchers do |t|
      t.references :card, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    # Watching is idempotent by nature — the UI is a toggle, but a double-submit
    # or a retried request must not be able to leave two rows behind. Enforced at
    # the DB, not only by CardWatcher's uniqueness validation (which races) or by
    # the controller's find_by. Mirrors board_favorites, indexed the same way;
    # card_members has no such index, which is why it's the weaker of the two
    # precedents here.
    add_index :card_watchers, [:card_id, :user_id], unique: true
  end
end
