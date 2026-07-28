class AddCardLimitToLists < ActiveRecord::Migration[7.1]
  def change
    # Nullable with no default on purpose: NULL means "no WIP limit", which is
    # what every existing list gets. It's a SOFT limit — the header shows
    # count/limit and tints when over, but nothing blocks card creation.
    add_column :lists, :card_limit, :integer
  end
end
