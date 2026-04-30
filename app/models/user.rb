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

  has_many :shared_boards,    through: :board_users, source: :board
  has_many :favorited_boards, through: :board_favorites, source: :board
  has_many :assigned_cards,   through: :card_members, source: :card

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
end
