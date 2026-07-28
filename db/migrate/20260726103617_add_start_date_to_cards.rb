class AddStartDateToCards < ActiveRecord::Migration[7.1]
  def change
    # Nullable with no default: NULL means "no start date", which is what every
    # existing card gets — so a card behaves exactly as before (a single point
    # on its due date) until someone sets one. Due-date reminders are keyed off
    # due_date only and are deliberately untouched by this column.
    add_column :cards, :start_date, :datetime
  end
end
