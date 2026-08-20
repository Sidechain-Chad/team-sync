class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Switch from :destroy to :nullify on the things that hold historical/audit
  # value — but in practice we never actually destroy users (see deactivate!),
  # so this :nullify is just a safety net for the rare DB-direct delete.
  has_many :boards,        dependent: :destroy   # boards die with their owner — keep :destroy
  has_many :board_users,   dependent: :destroy   # membership is current state, not history
  has_many :card_members,  dependent: :destroy   # same — current state
  has_many :comments,      dependent: :nullify   # historical — preserve the comment text
  has_many :activities,    dependent: :nullify   # historical — preserve the audit trail
  has_many :board_favorites, dependent: :destroy
  has_many :card_watchers,   dependent: :destroy   # current state, like card_members
  has_many :board_watchers,  dependent: :destroy   # current state, like card_watchers
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy

  has_many :shared_boards,    through: :board_users, source: :board
  has_many :favorited_boards, through: :board_favorites, source: :board
  has_many :assigned_cards,   through: :card_members, source: :card
  has_many :watched_cards,    through: :card_watchers, source: :card
  has_many :watched_boards,   through: :board_watchers, source: :board

  # :chip is 2x a h-8 chip (comment/activity/nav rows); :thumb is for the
  # h-16 profile identity block. NOT preprocessed — on Cloudinary these
  # named variants are only a fallback (see AvatarsHelper#avatar_image_url,
  # which builds Cloudinary's own transformation URLs instead), and
  # preprocessing would just enqueue the exact background processing that
  # path exists to avoid.
  has_one_attached :avatar do |attachable|
    attachable.variant :chip, resize_to_fill: [64, 64]
    attachable.variant :thumb, resize_to_fill: [160, 160]
  end

  # ---- Appearance ----
  #
  # The value is written into <html data-theme="..."> (see ApplicationHelper),
  # where CSS keys the whole dark palette off it. Light and dark only — a
  # "Match system"/prefers-color-scheme option used to exist here and was
  # removed by design (see the git history if you're looking for it).
  #
  # Unscoped (no `on:` context) on purpose, unlike the name validation below:
  # the theme switcher saves through a plain `update`, and an unvalidated column
  # feeding straight into an HTML attribute is how you get an injected attribute
  # value. The allowlist IS the sanitiser.
  THEMES = %w[light dark].freeze

  validates :theme, inclusion: { in: THEMES }

  # Only enforced on the Account > Profile name form (AccountController
  # passes context: :profile_update). Can't use `validates :name,
  # presence: true` unscoped — that would call the #name reader below,
  # which already falls back to the email prefix and so is NEVER blank,
  # making a plain presence validation a silent no-op. Checking the raw
  # attribute directly via a custom validation is what actually catches
  # a blank submission, and scoping it to :profile_update keeps every
  # other save path (deactivate!, Devise's own updates, fixtures) — none
  # of which ever set a name — from suddenly failing validation.
  validate :name_present_for_profile_update, on: :profile_update

  # Deliberately NOT scoped to :profile_update (or any context) — avatar
  # upload is its own action using a plain save (see AccountController),
  # specifically so it never rides the name-presence check above. Scoped
  # to attachment_changes so an unrelated save (deactivate!, Devise) never
  # re-validates an already-valid, already-attached avatar.
  validate :avatar_must_be_valid, if: -> { attachment_changes["avatar"].present? }

  # ---- Soft delete ----

  scope :active,      -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  def deactivated?
    deactivated_at.present?
  end

  def deactivate!
    transaction do
      update!(deactivated_at: Time.current)
      # Strip them from active assignments but keep their comments/activities intact.
      board_users.destroy_all
      card_members.destroy_all
      # Watching is an active subscription, not history — same category as
      # card_members. Without this a deactivated user keeps accruing comment and
      # due_soon notifications for every card they were watching.
      card_watchers.destroy_all
      # Same reasoning, board-level: without this a deactivated account keeps
      # accruing notifications for every board it watched.
      board_watchers.destroy_all
    end
  end

  def reactivate!
    update!(deactivated_at: nil)
  end

  # Override Devise so deactivated users can't log in.
  def active_for_authentication?
    super && !deactivated?
  end

  def inactive_message
    deactivated? ? :deactivated : super
  end

  # ---- existing methods ----

  def all_boards
    Board.where(user_id: id).or(Board.where(id: board_users.select(:board_id)))
  end

  def all_lists
    List.where(board_id: all_boards.select(:id))
  end

  def all_cards
    Card.where(list_id: all_lists.select(:id))
  end

  # ---- Listing scopes: the all_* scopes above, minus closed boards ----
  #
  # The all_* scopes back AUTHORIZATION (set_board, board_scoped_list,
  # every `find(params[...])` in the app) and must keep resolving a closed
  # board — otherwise its owner could never reach the page that reopens it.
  # These open_* scopes are the LISTING counterparts: use them anywhere boards
  # or their cards are enumerated or aggregated rather than looked up by id.
  # Two names instead of one flag is deliberate — it makes "did this call site
  # get the closed-board filter?" a grep, not a code read.
  def open_boards
    all_boards.merge(Board.open)
  end

  def open_lists
    List.where(board_id: open_boards.select(:id))
  end

  def open_cards
    Card.where(list_id: open_lists.select(:id))
  end

  def all_checklists
    Checklist.where(card_id: all_cards.select(:id))
  end

  def all_checklist_items
    ChecklistItem.where(checklist_id: all_checklists.select(:id))
  end

  def name
    return self[:name] if has_attribute?(:name) && self[:name].present?
    email.split('@').first.capitalize
  end

  def display_name
    deactivated? ? "#{name} (deactivated)" : name
  end

  def initials
    name.split.map(&:first).join.upcase.first(2)
  end

  # Opt-out: unknown / unset types default to on. Stored values are real JSON
  # booleans (see AccountController#update_settings).
  def notifies?(action)
    notification_preferences.fetch(action.to_s, true)
  end

  private

  def name_present_for_profile_update
    errors.add(:name, "can't be blank") if self[:name].blank?
  end

  ALLOWED_AVATAR_TYPES = %w[image/png image/jpeg image/webp].freeze

  def avatar_must_be_valid
    return unless avatar.attached?

    unless avatar.blob.content_type.in?(ALLOWED_AVATAR_TYPES)
      errors.add(:avatar, "must be a PNG, JPEG, or WebP")
    end

    if avatar.blob.byte_size > 5.megabytes
      errors.add(:avatar, "must be smaller than 5 MB")
    end
  end
end
