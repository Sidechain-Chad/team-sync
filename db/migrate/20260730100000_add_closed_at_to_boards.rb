class AddClosedAtToBoards < ActiveRecord::Migration[7.1]
  def change
    # Nullable with no default: NULL means "open", which is what every existing
    # board gets. Closing is reversible and non-destructive — nothing about a
    # board's lists, cards, or attachments changes, only its visibility in
    # listings (see Board.open and the filtering at each listing site).
    #
    # Indexed because essentially every board listing and cross-board card
    # aggregation in the app now filters on it.
    add_column :boards, :closed_at, :datetime
    add_index  :boards, :closed_at
  end
end
