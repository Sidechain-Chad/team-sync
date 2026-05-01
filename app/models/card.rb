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
  has_many_attached :attachments

  # NEW: labels
  has_many :card_labels, dependent: :destroy
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
