class CreateCardMembers < ActiveRecord::Migration[7.1]
  def change
    create_table :card_members do |t|
      t.references :card, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
