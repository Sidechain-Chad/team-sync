class ChecklistItem < ApplicationRecord
  belongs_to :checklist
  acts_as_list scope: :checklist

  validates :content, presence: true
end
