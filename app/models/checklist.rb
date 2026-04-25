class Checklist < ApplicationRecord
  belongs_to :card
  has_many :checklist_items, -> { order(position: :asc) }, dependent: :destroy

  acts_as_list scope: :card

  validates :title, presence: true

  def percent_complete
    return 0 if checklist_items.none?
    ((checklist_items.where(completed: true).count.to_f / checklist_items.count) * 100).round
  end
end
