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

  AVATAR_VARIANT_PX = { chip: 64, thumb: 160 }.freeze

  # URL for a user's avatar at the given named variant size.
  #
  # Active Storage variant processing round-trips the original through
  # Cloudinary (download, transform, re-upload) on first access — Cloudinary
  # normalizes/re-encodes the bytes, so the re-downloaded file fails Active
  # Storage's checksum (ActiveStorage::IntegrityError), 500-ing the redirect
  # endpoint. Cloudinary's own on-the-fly transformation URLs sidestep
  # Active Storage processing entirely, so we build those directly when the
  # blob lives on Cloudinary. Any other service (test adapter, local disk)
  # falls back to the named Active Storage variant as before.
  #
  # Checked via blob.service_name (the storage.yml service key, e.g.
  # "cloudinary" — a plain string column on the blob) rather than the
  # service instance's class: ActiveStorage::Service::CloudinaryService is
  # only autoloaded when a "cloudinary" service is actually configured
  # (not in the test environment), so referencing that constant directly
  # would raise NameError there.
  def avatar_image_url(user, variant: :chip)
    return nil unless user&.avatar&.attached?

    blob = user.avatar.blob

    if blob.service_name == "cloudinary"
      px = AVATAR_VARIANT_PX.fetch(variant)
      Cloudinary::Utils.cloudinary_url(
        blob.service.public_id(blob.key),
        resource_type: "image",
        width: px, height: px, crop: :fill, gravity: :face,
        fetch_format: :auto, quality: :auto
      )
    else
      url_for(user.avatar.variant(variant))
    end
  end
end
