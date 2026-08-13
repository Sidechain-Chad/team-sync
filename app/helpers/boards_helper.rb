module BoardsHelper
  include MediaHelper

  # Deterministic cover gradient for boards without an avatar — same board
  # always gets the same palette entry, so tiles look distinct from each
  # other but stable across page loads.
  # Golden Hour rebrand: warm-anchored set, with two cool counterpoints kept
  # so boards stay visually distinct from each other (an all-warm set makes
  # tiles blur together). Non-brand hues have no theme token, so they're
  # arbitrary-value hex pairs; ember reuses the brand-500/400 tokens directly.
  BOARD_COVER_GRADIENTS = [
    "from-brand-500 to-brand-400",         # ember
    "from-[#F59E0B] to-[#EA7317]",         # honey
    "from-[#B0552F] to-[#7C3F21]",         # clay
    "from-[#C2554F] to-[#F08A7E]",         # rosewood
    "from-[#7C4A6B] to-[#A9647F]",         # plum (warm purple)
    "from-[#6B7C2F] to-[#8FA34A]",         # moss
    "from-[#2F6F6B] to-[#4A9A8F]",         # dusk teal (cool counterpoint)
    "from-[#4A5A7C] to-[#6B7FA3]",         # slate blue (cool counterpoint)
  ].freeze

  def board_cover_gradient_classes(board)
    BOARD_COVER_GRADIENTS[board.id % BOARD_COVER_GRADIENTS.size]
  end

  # Which .board-canvas-rich-N class (application.css) gives the dark-mode
  # board canvas its per-board radial-highlight/radial-shadow/linear-base
  # treatment. Index-aligned with BOARD_COVER_GRADIENTS so a board's tile,
  # its light-mode canvas gradient, and its dark-mode rich canvas all come
  # from the same palette entry. Added unconditionally alongside
  # board_cover_gradient_classes in boards/show.html.erb — inert in light
  # mode, since .board-canvas-gradient's light-mode rule never references
  # the --rich-* variables this class sets.
  def board_canvas_rich_class(board)
    "board-canvas-rich-#{board.id % BOARD_COVER_GRADIENTS.size}"
  end

  # Tile thumbnail for board cards/switcher. :tile is a named variant (see
  # Board) — no `.processed` here; see MediaHelper#media_transform_url for
  # why Cloudinary needs its own transformation URL instead. An uploaded
  # background takes precedence over the avatar, so the index tile matches
  # what the board itself shows on open; falls back to the gradient (nil)
  # when neither is attached.
  def board_tile_url(board)
    if board.background.attached?
      media_transform_url(board.background, variant: :tile, width: 400, height: 160)
    elsif board.avatar.attached?
      media_transform_url(board.avatar, variant: :tile, width: 400, height: 160)
    end
  end

  # Full-bleed wallpaper for the board canvas. :canvas is a named variant
  # (see Board); routed through MediaHelper#media_transform_url for the same
  # reason as board_tile_url — fresh Cloudinary variant processing 500s on
  # IntegrityError. gravity: :auto centers the fill on the salient region.
  def board_background_url(board)
    return nil unless board.background.attached?
    media_transform_url(board.background, variant: :canvas, width: 2000, height: 1200, crop: :fill, gravity: :auto)
  end
end
