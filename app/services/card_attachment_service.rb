# Centralizes the "attach files to a card" operation: filters out empty
# uploads, runs validation, attaches via Active Storage, and logs one
# activity entry per file. Returns a Result struct so callers can
# branch on success without raising.
#
# Used by:
#   - CardsController#update  → multi-file upload from the modal
#   - (future) any other path that needs to add files to a card
class CardAttachmentService
  MAX_SIZE = 25.megabytes

  # Mime types that are safe to accept. Tuned for a production-company
  # use case: stills, video clips, audio refs, contracts, spreadsheets,
  # zipped deliverables. Bump or trim as the customer's needs become
  # clearer; reject-by-default is the safer side to err on.
  ALLOWED_TYPES = %w[
    image/png image/jpeg image/jpg image/gif image/webp image/svg+xml
    application/pdf
    video/mp4 video/quicktime video/webm video/x-matroska
    audio/mpeg audio/mp4 audio/wav audio/x-wav audio/webm audio/ogg audio/aac audio/flac
    application/zip application/x-zip-compressed application/x-zip
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.ms-excel
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    text/plain text/csv
  ].freeze

  # Fallback for when the browser sends a useless content_type
  # (application/octet-stream, missing, or a vendor-specific alias we
  # haven't seen). We trust the extension as a secondary signal — the
  # size cap still applies and we still won't accept .exe, .bat, etc.
  ALLOWED_EXTENSIONS = %w[
    .png .jpg .jpeg .gif .webp .svg
    .pdf
    .mp4 .mov .webm .mkv
    .mp3 .m4a .wav .ogg .aac .flac
    .zip
    .doc .docx .xls .xlsx
    .txt .csv
  ].freeze

  Result = Struct.new(:success?, :attachments, :error, keyword_init: true)

  def initialize(card:, user:, files:)
    @card  = card
    @user  = user
    # Multipart file_field arrays start with an empty string Rails inserts
    # to ensure the param exists even when nothing's selected. Drop it.
    @files = Array(files).reject(&:blank?)
  end

  def call
    return Result.new(success?: true, attachments: []) if @files.empty?

    if (invalid = @files.find { |f| !valid?(f) })
      return Result.new(success?: false, attachments: [], error: error_for(invalid))
    end

    @card.attachments.attach(@files)

    # Active Storage appends, so the most recently created N attachments
    # are the ones we just uploaded. Log one activity per filename so
    # the activity feed shows each file individually.
    fresh = @card.attachments.order(created_at: :desc).limit(@files.size).to_a
    fresh.each { |att| @card.log_activity(@user, "added_attachment", att.filename.to_s) }

    Result.new(success?: true, attachments: fresh, error: nil)
  end

  private

  def valid?(file)
    return false if file.size > MAX_SIZE
    return true if ALLOWED_TYPES.include?(file.content_type)
    ALLOWED_EXTENSIONS.include?(File.extname(file.original_filename.to_s).downcase)
  end

  def error_for(file)
    name = file.original_filename
    if file.size > MAX_SIZE
      "#{name} is over 25MB and can't be attached."
    else
      "#{name} (#{file.content_type}) isn't an allowed file type."
    end
  end
end
