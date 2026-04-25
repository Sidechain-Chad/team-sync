class Board < ApplicationRecord
  belongs_to :user
  has_many :lists, -> { order(position: :asc) }, dependent: :destroy
  has_many :board_users, dependent: :destroy
  has_many :members, through: :board_users, source: :user
  has_many :labels, dependent: :destroy

  has_one_attached :avatar

  validates :name, presence: true

  # Seed the default Trello-style label palette on every new board so
  # users have something to pick from immediately.
  after_create :seed_default_labels

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
end
