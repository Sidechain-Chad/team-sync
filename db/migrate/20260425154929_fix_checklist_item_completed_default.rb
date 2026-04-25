class FixChecklistItemCompletedDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :checklist_items, :completed, from: nil, to: false
    ChecklistItem.where(completed: nil).update_all(completed: false)
    change_column_null :checklist_items, :completed, false
  end
end
