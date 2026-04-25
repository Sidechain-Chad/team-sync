class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :boards, dependent: :destroy
  has_many :board_users, dependent: :destroy
  has_many :shared_boards, through: :board_users, source: :board
  has_many :card_members, dependent: :destroy
  has_many :assigned_cards, through: :card_members, source: :card
  has_many :comments, dependent: :destroy

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

  def initials
    name.split.map(&:first).join.upcase.first(2)
  end
end
