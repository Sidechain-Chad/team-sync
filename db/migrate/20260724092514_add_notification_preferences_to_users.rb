class AddNotificationPreferencesToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :notification_preferences, :jsonb, default: {}, null: false
  end
end
