# A user watching a card: they receive the card's notifications without being a
# member. Trello's "Watch".
#
# Modelled on BoardFavorite rather than CardMember — both are per-user toggles
# with no attributes of their own, but BoardFavorite is the one that carries the
# uniqueness guarantee (validation + unique index), which a toggle needs.
class CardWatcher < ApplicationRecord
  belongs_to :card
  belongs_to :user

  # Belt to the unique index's braces: this gives a clean validation error
  # instead of a RecordNotUnique, while the index is what actually holds under a
  # race. Same pairing as BoardFavorite.
  validates :card_id, uniqueness: { scope: :user_id }
end
