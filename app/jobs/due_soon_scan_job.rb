class DueSoonScanJob < ApplicationJob
  def perform
    Card.due_reminder_pending.includes(:members).find_each do |card|
      card.members.each do |member|
        Notification.deliver(recipient: member, actor: nil, notifiable: card, action: "due_soon")
      end
      card.update_column(:due_reminder_sent_at, Time.current)
    end
  end
end
