class Card < ApplicationRecord
  include PgSearch::Model

  belongs_to :list
  belongs_to :assignee, class_name: 'User', optional: true

  # NEW: Allow multiple members
  has_many :card_members, dependent: :destroy
  has_many :members, through: :card_members, source: :user
  has_many :comments, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :checklists, -> { order(position: :asc) }, dependent: :destroy

  # :cover is a named variant. NOT preprocessed — on Cloudinary it's only
  # a fallback (see CardsHelper#card_cover_url / MediaHelper#media_transform_url,
  # which builds Cloudinary's own transformation URL instead), and
  # preprocessing would just enqueue the exact background processing that
  # path exists to avoid.
  has_many_attached :attachments do |attachable|
    attachable.variant :cover, resize_to_fill: [560, 200]
    attachable.variant :thumb, resize_to_limit: [112, 80]
  end

  # NEW: labels
  # CardLabel is a bare join row (no callbacks, no dependents of its own),
  # so a bulk DELETE is safe and avoids one query per row on card destroy.
  has_many :card_labels, dependent: :delete_all
  has_many :labels, through: :card_labels

  # 1. Scope: This ensures that if I move a card to position 1,
  #    it only affects cards in the SAME list, not every card in the database.
  acts_as_list scope: :list

  validates :title, presence: true

  # Multi-field search across title, description, AND associated comments.
  # Two strategies combined:
  #
  #   :tsearch  — Postgres full-text search. Stems words ("running" finds
  #               "ran"), ignores stop words, weights matches by field.
  #               Title is weighted A (highest), description B, comments C.
  #
  #   :trigram  — Fuzzy/typo tolerance. Catches misspellings tsearch misses.
  #
  # PgSearch combines both rankings, so an exact-but-stemmed title match
  # outranks a fuzzy comment match — which is what you want.
  pg_search_scope :search_for,
                  against: {
                    title:       'A',
                    description: 'B'
                  },
                  associated_against: {
                    comments: { content: 'C' }
                  },
                  using: {
                    tsearch: {
                      prefix:     true,        # "wet" matches "wetland"
                      dictionary: "english"
                    },
                    trigram: {
                      threshold: 0.2,
                      only:      [:title, :description]  # skip fuzzy on comments — too noisy
                    }
                  }

  # Trello-style soft delete. Archived cards stay in the DB but
  # are hidden from the board view by default.
  scope :active,   -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  scope :with_location, -> {
    where.not(latitude: nil, longitude: nil)
  }

  # Cards whose reminder is due to fire: approaching (within the window), not
  # done, not archived, and not already reminded for this due date.
  scope :due_reminder_pending, -> {
    active.where(completed: false, due_reminder_sent_at: nil)
          .where(due_date: Time.current..24.hours.from_now)
  }

  # When the due date changes, the card becomes eligible for a fresh reminder.
  # update_column (used by the scan to stamp sent_at) skips callbacks, so this
  # never fights the scan.
  before_save :clear_due_reminder, if: :will_save_change_to_due_date?
  def clear_due_reminder
    self.due_reminder_sent_at = nil
  end

  # Association tree the cards/_card partial needs to render without an
  # N+1: labels, members, checklist items, and attachment blobs (for the
  # cover image / attachment count). Shared by every place that re-renders
  # potentially many cards at once — boards#show, lists#move, and the
  # labels turbo-stream broadcasts.
  BOARD_PAGE_INCLUDES = [
    :labels,
    { members: { avatar_attachment: :blob } },
    { checklists: :checklist_items },
    { attachments_attachments: :blob }
  ].freeze

  scope :with_board_page_includes, -> { includes(BOARD_PAGE_INCLUDES) }

  def location?
    latitude.present? && longitude.present?
  end

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def to_param
    "#{id}-#{title.parameterize}"
  end

  def log_activity(user, action, description = nil)
    activities.create(user: user, action: action, description: description)
  end

  # Due-date status helpers — used by views to color the due-date pill.
  # :complete > :overdue > :due_soon > :upcoming > :none
  def due_status
    return :none     if due_date.blank?
    return :complete if completed?
    return :overdue  if due_date < Time.current
    return :due_soon if due_date < 24.hours.from_now
    :upcoming
  end

  def overdue?
    due_status == :overdue
  end

  # Returns the first attached image, used as the card cover on the board.
  # Skips non-image attachments (PDFs, docs etc.) so a non-image first attachment
  # doesn't suppress the cover from a later image.
  def cover_image
    return nil unless attachments.attached?
    attachments.find { |att| att.image? }
  end
end
