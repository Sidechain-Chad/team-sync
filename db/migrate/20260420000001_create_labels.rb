class CreateLabels < ActiveRecord::Migration[7.1]
  def change
    create_table :labels do |t|
      t.references :board, null: false, foreign_key: true
      t.string :name
      t.string :color, null: false
      t.timestamps
    end

    create_table :card_labels do |t|
      t.references :card,  null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true
      t.timestamps
    end

    add_index :card_labels, [:card_id, :label_id], unique: true
  end
end
