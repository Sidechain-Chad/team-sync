class AddArchivedAtToCards < ActiveRecord::Migration[7.1]
  def change
    add_column :cards, :archived_at, :datetime
  end
end
