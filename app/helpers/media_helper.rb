module MediaHelper
  # Shared Cloudinary-vs-Active-Storage URL branching for any image
  # attachment (user avatars, card covers, board tiles).
  #
  # Fresh Active Storage variant/analysis processing round-trips the
  # original through Cloudinary (download, transform, re-upload) —
  # Cloudinary normalizes/re-encodes the bytes, so the re-downloaded file
  # then fails Active Storage's checksum (ActiveStorage::IntegrityError),
  # 500-ing the redirect endpoint. Cloudinary's own on-the-fly
  # transformation URLs sidestep Active Storage processing entirely, so we
  # build those directly when the blob lives on Cloudinary. Any other
  # service (test adapter, local disk) falls back to the caller's named
  # Active Storage variant, unchanged.
  #
  # +attachable+ is anything that responds to both #blob and #variant — an
  # ActiveStorage::Attached::One entry (user.avatar, board.avatar) or an
  # ActiveStorage::Attachment (card.cover_image).
  #
  # Checked via blob.service_name (the storage.yml service key, a plain
  # string column) rather than the service instance's class:
  # ActiveStorage::Service::CloudinaryService is only autoloaded when a
  # "cloudinary" service is actually configured (not in the test
  # environment), so referencing that constant directly would raise
  # NameError there.
  def media_transform_url(attachable, variant:, width:, height:, crop: :fill, gravity: nil)
    return nil unless attachable

    blob = attachable.blob
    return nil unless blob

    if blob.service_name == "cloudinary"
      options = {
        resource_type: "image",
        width: width, height: height, crop: crop,
        fetch_format: :auto, quality: :auto
      }
      options[:gravity] = gravity if gravity
      Cloudinary::Utils.cloudinary_url(blob.service.public_id(blob.key), **options)
    else
      url_for(attachable.variant(variant))
    end
  end
end
