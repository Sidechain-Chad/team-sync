class AddLocationToCards < ActiveRecord::Migration[7.1]
  def change
    add_column :cards, :latitude,         :decimal, precision: 10, scale: 6
    add_column :cards, :longitude,        :decimal, precision: 10, scale: 6
    add_column :cards, :location_name,    :string  # short label e.g. "Williamsburg, Brooklyn"
    add_column :cards, :location_address, :string  # full normalized address from Mapbox

    # Powers the per-board map view: "give me every card in this list_id
    # set that has coordinates." Partial index — rows without coords are
    # the majority and don't need to be in the index.
    add_index :cards, [:latitude, :longitude],
              where: "latitude IS NOT NULL AND longitude IS NOT NULL",
              name: "index_cards_on_coordinates"
  end
end
