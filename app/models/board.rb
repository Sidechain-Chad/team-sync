class Board < ApplicationRecord
  include PgSearch::Model

  belongs_to :user
  has_many :lists, -> { order(position: :asc) }, dependent: :destroy
  has_many :board_users, dependent: :destroy
  has_many :members, through: :board_users, source: :user
  has_many :labels, dependent: :destroy
  has_many :board_favorites, dependent: :destroy
  has_many :favorited_by_users, through: :board_favorites, source: :user

  # :tile is a named variant. NOT preprocessed — on Cloudinary it's only a
  # fallback (see boards/_cover.html.erb / MediaHelper#media_transform_url,
  # which builds Cloudinary's own transformation URL instead), and
  # preprocessing would just enqueue the exact background processing that
  # path exists to avoid.
  has_one_attached :avatar do |attachable|
    attachable.variant :tile, resize_to_fill: [400, 160]
  end

  # :canvas/:tile are named variants, NOT preprocessed — on Cloudinary
  # they're only a fallback (see BoardsHelper#board_background_url /
  # MediaHelper#media_transform_url, which builds Cloudinary's own
  # transformation URL instead), and preprocessing would just enqueue the
  # exact background processing that path exists to avoid.
  has_one_attached :background do |attachable|
    attachable.variant :canvas, resize_to_fill: [2000, 1200]  # full-bleed wallpaper
    attachable.variant :tile,   resize_to_fill: [400, 160]    # index-tile crop
  end

  validates :name, presence: true

  # Single-field trigram search on board name. against: :name +
  # ranked_by similarity gives us typo-tolerant matching ranked by
  # how close the match is. Threshold 0.2 is forgiving enough for
  # real typos but filters out spurious 1-char overlaps.
  pg_search_scope :search_for,
                  against: :name,
                  using: {
                    trigram: {
                      threshold: 0.2,
                      word_similarity: true
                    }
                  }

  def favorited_by?(user)
    return false unless user
    board_favorites.exists?(user_id: user.id)
  end

  def owner?(user)
    return false unless user
    user_id == user.id
  end

  def active_members
    ([user] + members).uniq.reject(&:deactivated?)
  end

  # Seed the default Trello-style label palette on every new board so
  # users have something to pick from immediately.
  after_create :seed_default_labels
  after_create :seed_default_lists

  def invite_users(emails_string, inviter)
    return if emails_string.blank?

    emails = emails_string.split(',').map(&:strip)
    emails.each do |email|
      user = User.find_by(email: email)
      if user && user != inviter
        board_users.find_or_create_by(user: user)
      end
    end
  end

  private

  def seed_default_labels
    Label::COLORS.each { |color| labels.create!(color: color) }
  end

  # Every new board starts with three Trello-style lists so the user has
  # somewhere to drop cards immediately. Position is set explicitly so they
  # render in the intended order regardless of acts_as_list defaults.
  def seed_default_lists
    ["To Do", "Doing", "Done"].each_with_index do |name, index|
      lists.create!(name: name, position: index + 1)
    end
  end
end
