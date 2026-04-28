module AvatarsHelper
  # Stable colour per user — same user always gets the same colour. We hash
  # on user.id so the colour doesn't change when display_name does.
  AVATAR_PALETTE = [
    { soft: "bg-blue-100 text-blue-700",       border: "border-blue-200",       solid: "bg-blue-500" },
    { soft: "bg-emerald-100 text-emerald-700", border: "border-emerald-200",    solid: "bg-emerald-500" },
    { soft: "bg-amber-100 text-amber-800",     border: "border-amber-200",      solid: "bg-amber-500" },
    { soft: "bg-rose-100 text-rose-700",       border: "border-rose-200",       solid: "bg-rose-500" },
    { soft: "bg-violet-100 text-violet-700",   border: "border-violet-200",     solid: "bg-violet-500" },
    { soft: "bg-cyan-100 text-cyan-700",       border: "border-cyan-200",       solid: "bg-cyan-500" },
    { soft: "bg-orange-100 text-orange-700",   border: "border-orange-200",     solid: "bg-orange-500" },
    { soft: "bg-fuchsia-100 text-fuchsia-700", border: "border-fuchsia-200",    solid: "bg-fuchsia-500" }
  ].freeze

  # For light pill-style avatars (board faces, member rows, +N initials).
  def avatar_soft_classes(user)
    return "bg-gray-200 text-gray-500 border-gray-200" if user.nil?
    p = AVATAR_PALETTE[user.id % AVATAR_PALETTE.size]
    "#{p[:soft]} #{p[:border]}"
  end

  # For solid filled avatars (currently used by comment authors).
  def avatar_solid_classes(user)
    return "bg-gray-400 text-white" if user.nil?
    "#{AVATAR_PALETTE[user.id % AVATAR_PALETTE.size][:solid]} text-white"
  end
end
