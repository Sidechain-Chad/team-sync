class Activity < ApplicationRecord
  belongs_to :user, optional: true
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
    when "edited_description"
      "edited the description"
    when "archived"
      "archived this card"
    when "unarchived"
      "restored this card from the archive"
    else
      description
    end
  end
end
