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
    when "set_due_date"
      "set the due date to #{description}"
    when "removed_due_date"
      "removed the due date"
    when "completed_card"
      "marked this card as complete"
    when "uncompleted_card"
      "marked this card as incomplete"
    when "renamed"
      "renamed this card to \"#{description}\""
    when "archived"
      "archived this card"
    when "unarchived"
      "restored this card from the archive"
    else
      # Defensive fallback so old rows from before the cleanup never render
      # as a blank row in the feed.
      description.presence || "made a change to this card"
    end
  end
end
