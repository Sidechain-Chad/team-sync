# A user watching a board: they receive notifications for activity across all
# its cards, and when cards are added, without being a member of any specific
# card. Trello's "Watch" at the board level.
#
# Modelled on CardWatcher (which itself models BoardFavorite) — same shape: a
# per-user toggle with no attributes of its own, plus the uniqueness guarantee
# (validation + unique index) a toggle needs.
class BoardWatcher < ApplicationRecord
  belongs_to :board
  belongs_to :user

  # Belt to the unique index's braces: this gives a clean validation error
  # instead of a RecordNotUnique, while the index is what actually holds under a
  # race. Same pairing as CardWatcher/BoardFavorite.
  validates :board_id, uniqueness: { scope: :user_id }
end
