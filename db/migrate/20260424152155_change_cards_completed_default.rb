class ChangeCardsCompletedDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :cards, :completed, from: nil, to: false
    change_column_null :cards, :completed, false, false
  end
end
