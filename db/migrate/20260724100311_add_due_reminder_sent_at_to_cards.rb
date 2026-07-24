class AddDueReminderSentAtToCards < ActiveRecord::Migration[7.1]
  def change
    add_column :cards, :due_reminder_sent_at, :datetime
  end
end
