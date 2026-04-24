class CreateChecklists < ActiveRecord::Migration[7.1]
  def change
    create_table :checklists do |t|
      t.references :card, null: false, foreign_key: true
      t.string :title
      t.integer :position

      t.timestamps
    end
  end
end
