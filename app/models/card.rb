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

  # Polymorphic, so unlike recipient_id/actor_id this can't be backed by a real
  # foreign key — nothing at the DB level stops a destroyed card from leaving its
  # notifications behind. Without this cascade an orphan's `notification.card` is
  # nil, which used to take the whole bell dropdown down (see
  # notifications/_notification, which is now also defensive about it).
  has_many :notifications, as: :notifiable, dependent: :destroy

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

  # Only meaningful when BOTH dates are set — either one alone is fine, and so
  # is neither. Deliberately rejects rather than reordering: silently swapping
  # the two would hide a typo instead of surfacing it.
  validate :start_date_not_after_due_date

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

  # Duplicates this card's content (not its history) into `list`. Copies
  # labels/members as brand new join rows (never touching the source's own
  # card_labels/card_members), checklists+items (each item's completed reset
  # to false — the dominant use of copy-card is "run this task again," so a
  # fresh checklist is the useful default), and attachments.
  #
  # Attachments are copied by attaching the SAME blobs (attach(blob), not
  # attach(io:...)) — a new ActiveStorage::Attachment row per file, pointing
  # at the already-uploaded blob. No re-upload, no Cloudinary round-trip.
  # This is safe against the copy (or the original) later deleting one of
  # its attachments: a DB foreign key on active_storage_attachments.blob_id
  # means ActiveStorage::Blob#purge rescues ActiveRecord::InvalidForeignKey
  # and leaves the blob (and its file) alone as long as another attachment
  # row still references it — see AttachmentsControllerTest's shared-blob
  # deletion-safety test, which is what this behavior is pinned by.
  #
  # Deliberately does NOT copy comments or activities (Trello doesn't
  # either — they belong to the original card's own history).
  # completed/archived_at/comments_count/due_reminder_sent_at are reset
  # rather than copied: due_reminder_sent_at especially, since inheriting a
  # non-nil stamp would make the copy look "already reminded" and it would
  # never get a due-soon notification of its own.
  #
  # card_labels/card_members are built directly (mass-assigned via
  # label_ids=/member_ids=) rather than through CardLabelsController /
  # CardMembersController — that's why copying a card with members never
  # sends added_to_card notifications; that trigger lives only in
  # CardMembersController#create, not a model callback.
  #
  # No explicit position is set on the copy or its checklists/items —
  # acts_as_list's create callback appends each to the bottom of its scope,
  # which is exactly "land last in the target list" for the card itself.
  def copy_to(list:, title:, user:)
    new_title = title.presence || self.title
    copy = nil

    transaction do
      copy = list.cards.create!(
        title: new_title,
        description: description,
        due_date: due_date,
        latitude: latitude,
        longitude: longitude,
        location_name: location_name,
        location_address: location_address,
        assignee_id: assignee_id,
        completed: false,
        archived_at: nil,
        due_reminder_sent_at: nil
      )

      copy.label_ids = label_ids
      copy.member_ids = member_ids
      copy.attachments.attach(attachments.map(&:blob)) if attachments.attached?

      checklists.each do |checklist|
        copied_checklist = copy.checklists.create!(title: checklist.title)
        checklist.checklist_items.each do |item|
          copied_checklist.checklist_items.create!(content: item.content, completed: false)
        end
      end

      copy.log_activity(user, "copied", self.title)
    end

    copy
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

  # True only when the card spans real calendar time. Everything date-range
  # (the Planner's bars) hangs off this, which is what makes a nil start_date
  # behave exactly as before: no range, so a single point on the due date.
  def date_range?
    start_date.present? && due_date.present?
  end

  # Every calendar day this card occupies on the Planner, in order. A range
  # covers start..due inclusive; anything else is just the due day, which is
  # the pre-start_date behaviour. Returns [] for an undated card.
  def planner_days
    return [] if due_date.blank?
    return [due_date.to_date] unless date_range?

    (start_date.to_date..due_date.to_date).to_a
  end

  # Returns the first attached image, used as the card cover on the board.
  # Skips non-image attachments (PDFs, docs etc.) so a non-image first attachment
  # doesn't suppress the cover from a later image.
  def cover_image
    return nil unless attachments.attached?
    attachments.find { |att| att.image? }
  end

  private

  def start_date_not_after_due_date
    return if start_date.blank? || due_date.blank?
    return if start_date <= due_date

    errors.add(:start_date, "must be on or before the due date")
  end
end
