module BoardsHelper
  # Deterministic cover gradient for boards without an avatar — same board
  # always gets the same palette entry, so tiles look distinct from each
  # other but stable across page loads.
  BOARD_COVER_GRADIENTS = [
    "from-blue-500 to-indigo-600",
    "from-emerald-500 to-teal-600",
    "from-orange-400 to-rose-500",
    "from-purple-500 to-fuchsia-600",
    "from-cyan-500 to-blue-600",
    "from-amber-400 to-orange-600",
    "from-pink-500 to-rose-600",
    "from-lime-500 to-emerald-600",
  ].freeze

  def board_cover_gradient_classes(board)
    BOARD_COVER_GRADIENTS[board.id % BOARD_COVER_GRADIENTS.size]
  end
end
