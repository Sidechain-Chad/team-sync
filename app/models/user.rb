class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :boards, dependent: :destroy
  has_many :board_users, dependent: :destroy
  has_many :shared_boards, through: :board_users, source: :board
  has_many :card_members, dependent: :destroy
  has_many :assigned_cards, through: :card_members, source: :card
  has_many :comments, dependent: :destroy

  def name
    return self[:name] if has_attribute?(:name) && self[:name].present?
    email.split('@').first.capitalize
  end

  def initials
    name.split.map(&:first).join.upcase.first(2)
  end
end
