class AddCommentsCountToCards < ActiveRecord::Migration[7.1]
  def change
    add_column :cards, :comments_count, :integer, default: 0, null: false

    # Backfill so a fresh db:migrate produces correct counts, not zeros.
    reversible do |dir|
      dir.up do
        Card.reset_column_information
        Card.find_each { |card| Card.reset_counters(card.id, :comments) }
      end
    end
  end
end
