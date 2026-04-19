class AddDueDateAndCompletedToCards < ActiveRecord::Migration[7.1]
  def change
    add_column :cards, :due_date,  :datetime
    add_column :cards, :completed, :boolean, default: false, null: false
  end
end
