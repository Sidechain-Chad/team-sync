class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :boards, dependent: :destroy
  has_many :board_users, dependent: :destroy
  has_many :shared_boards, through: :board_users, source: :board

  def name
    # If a name column exists in the DB, use it.
    # Otherwise, take the part of the email before the '@'
    return self[:name] if has_attribute?(:name) && self[:name].present?

    email.split('@').first.capitalize
  end

  def initials
    # Takes the first letter of first and last name and upcases them
    name.split.map(&:first).join.upcase.first(2)
  end
end
