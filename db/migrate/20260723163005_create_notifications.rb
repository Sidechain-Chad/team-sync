class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.bigint :recipient_id, null: false
      t.bigint :actor_id # nullable — the user who caused it (may be absent for system events)
      t.references :notifiable, polymorphic: true, null: false
      t.string :action, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_foreign_key :notifications, :users, column: :recipient_id
    add_foreign_key :notifications, :users, column: :actor_id

    add_index :notifications, :actor_id
    # Composite index covers both the hot paths: unread count
    # (WHERE recipient_id = ? AND read_at IS NULL) and the recent feed
    # (WHERE recipient_id = ? ORDER BY created_at) both filter on
    # recipient_id first, so a single composite index serves both instead
    # of two separate single-column indexes.
    add_index :notifications, [:recipient_id, :read_at]
  end
end
