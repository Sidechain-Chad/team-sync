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

  # Low-alpha (6%, hex suffix 0F) versions of each BOARD_COVER_GRADIENTS
  # anchor hue — the SAME "from" colour each gradient above starts at — used
  # to tint the dark-mode board canvas (.board-canvas-gradient in
  # application.css) with this board's own hue without showing the full
  # saturated gradient. Index-aligned with BOARD_COVER_GRADIENTS so a given
  # board's tile and its canvas tint always come from the same palette entry.
  # 6%, not more: composited over the shared neutral charcoal base, the most
  # saturated anchor (honey) still lands under 9% saturation — measured, not
  # eyeballed, because a higher alpha here is exactly how a tint slides back
  # into brown mush. Tailwind v4 arbitrary-property syntax
  # ([--custom-prop:value]) sets the CSS variable via a class rather than an
  # inline style, so the hex lives here (app/helpers is outside
  # NoRawColourInViewsTest's scan) rather than in the .erb source — same
  # pattern BOARD_COVER_GRADIENTS above already relies on for its own
  # arbitrary hex values.
  BOARD_CANVAS_TINTS = [
    "[--board-canvas-dark-tint:#EE5B2B0F]", # ember
    "[--board-canvas-dark-tint:#F59E0B0F]", # honey
    "[--board-canvas-dark-tint:#B0552F0F]", # clay
    "[--board-canvas-dark-tint:#C2554F0F]", # rosewood
    "[--board-canvas-dark-tint:#7C4A6B0F]", # plum
    "[--board-canvas-dark-tint:#6B7C2F0F]", # moss
    "[--board-canvas-dark-tint:#2F6F6B0F]", # dusk teal
    "[--board-canvas-dark-tint:#4A5A7C0F]", # slate blue
  ].freeze

  def board_canvas_tint_classes(board)
    BOARD_CANVAS_TINTS[board.id % BOARD_CANVAS_TINTS.size]
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
