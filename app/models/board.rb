class Board < ApplicationRecord
  include PgSearch::Model

  belongs_to :user
  has_many :lists, -> { order(position: :asc) }, dependent: :destroy
  has_many :board_users, dependent: :destroy
  has_many :members, through: :board_users, source: :user
  has_many :labels, dependent: :destroy
  has_many :board_favorites, dependent: :destroy
  has_many :favorited_by_users, through: :board_favorites, source: :user

  # Watching: receive this board's cards' notifications, and be told when a
  # card is added, without being a member of any specific card. Widens
  # Card#subscribers (members ∪ card watchers ∪ board watchers) for every card
  # on this board — see that method for the audience it does and doesn't reach.
  has_many :board_watchers, dependent: :destroy
  has_many :watchers, through: :board_watchers, source: :user

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

  # ---- Close / reopen ----
  #
  # Closing hides a board from every listing and cross-board aggregation while
  # leaving it fully intact and reachable by direct URL, so its owner can reopen
  # it. Deliberately NOT applied inside User#all_boards / #all_lists / #all_cards:
  # those back authorization (BoardsController#set_board,
  # CardsController#board_scoped_list), and scoping them would make a closed
  # board 404 — including the very page that offers Reopen. Filtering happens at
  # the listing/aggregation sites instead.
  scope :open,   -> { where(closed_at: nil) }
  scope :closed, -> { where.not(closed_at: nil) }

  def closed?
    closed_at.present?
  end

  def close!
    update!(closed_at: Time.current)
  end

  def reopen!
    update!(closed_at: nil)
  end

  # Duplicates this board — its labels, lists, active cards, members, avatar and
  # background — with `user` as the OWNER of the copy.
  #
  # LABEL REMAPPING is the whole reason this can't just loop List#copy_to. Labels
  # belong_to :board, and Card#copy_to's default `copy.label_ids = label_ids`
  # would attach THIS board's label rows to cards on the new board: cross-board
  # references that render the wrong labels and break the moment a source label is
  # renamed, recoloured or deleted. So new Label rows are created on the copy
  # first, a {source_label_id => new_label_id} map is built, and every card copy
  # translates through it.
  #
  # Copied:  labels (as new rows), lists in position order, each list's ACTIVE
  #          cards with their full association tree, board_users, avatar and
  #          background (the SAME blobs — no re-upload, no Cloudinary round trip;
  #          the active_storage_attachments → blobs FK makes sharing safe, and
  #          this is exactly what card attachments already do).
  # Not copied: favourites (personal), closed_at (a copy is always open,
  #          regardless of the source), archived cards, comments, activities, card
  #          watchers AND board watchers (personal subscription — same reasoning
  #          as card copy; a board watcher is simply never referenced anywhere
  #          in this method, so there's nothing to strip).
  #
  # board_users ARE copied deliberately: those users already had access to the
  # source, and leaving them out would strand copied card_members on a board they
  # can't open — inconsistent state we'd then have to go and strip.
  #
  # One transaction for the entire board, so a failure part-way through can never
  # leave a half-copied board behind.
  #
  # Note the seeded-defaults dance: Board's after_create callbacks give every new
  # board ten labels and three lists, which a copy must not keep. They're removed
  # inside the transaction before the real content is built.
  def copy_to(user:, name: nil)
    copy = nil

    transaction do
      copy = Board.create!(name: name.presence || "Copy of #{self.name}", user: user)

      # seed_default_labels / seed_default_lists fired on create. A copy brings its
      # own, so clear the defaults rather than ending up with both.
      copy.lists.destroy_all
      copy.labels.destroy_all

      label_map = labels.each_with_object({}) do |label, map|
        map[label.id] = copy.labels.create!(name: label.name, color: label.color).id
      end

      lists.order(:position).each do |list|
        list.copy_to(board: copy, name: list.name, user: user, label_map: label_map)
      end

      # The copier is skipped: they're the OWNER of the copy, so a board_users row
      # for them would be redundant (all_boards already covers owned boards, and
      # active_members uniq's the two lists). Everyone else who could see the
      # source can see the copy. Note the SOURCE's owner is not a board_user and
      # so does not carry across — the copy belongs to whoever made it.
      board_users.where.not(user_id: user.id).each do |bu|
        copy.board_users.create!(user_id: bu.user_id)
      end

      copy.avatar.attach(avatar.blob) if avatar.attached?
      copy.background.attach(background.blob) if background.attached?
    end

    copy
  end

  def favorited_by?(user)
    return false unless user
    board_favorites.exists?(user_id: user.id)
  end

  # Mirrors Card#watched_by? — same shape for the same kind of per-user toggle.
  # `exists?` costs one query per render, fine for the single board a page
  # shows; the boards-index tile calls this once per tile (see #watched_by?
  # in the tile partial), which is the same cost the favorite star already
  # pays per tile.
  def watched_by?(user)
    return false unless user
    board_watchers.exists?(user_id: user.id)
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
