class Activity < ApplicationRecord
  belongs_to :user
  belongs_to :card

  validates :action, presence: true

  after_create_commit do
    broadcast_prepend_to card, target: "activities_and_comments", partial: "activities/activity"
  end

  def message
    case action
    when "created"
      "created this card"
    when "moved"
      "moved this card from #{description}"
    when "added_checklist"
      "added checklist #{description} to this card"
    when "completed_checklist_item"
      "completed #{description} on this card"
    when "added_attachment"
      "attached #{description} to this card"
    else
      description
    end
  end
end
