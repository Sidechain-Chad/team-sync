class DueSoonScanJob < ApplicationJob
  def perform
    # BOTH associations are preloaded because Card#subscribers reads both. When
    # this only notified members it only needed `:members`; leaving it that way
    # after the switch to `subscribers` issues one `users INNER JOIN
    # card_watchers` per due card — an N+1 that grows with the number of due
    # cards. Pinned by a flat-lookup-query test in DueSoonScanJobTest whose
    # detection is proven by dropping :watchers here (measured: the lookup count
    # goes from flat-at-5 to 4 + one per card).
    Card.due_reminder_pending.includes(:members, :watchers).find_each do |card|
      card.subscribers.each do |subscriber|
        Notification.deliver(recipient: subscriber, actor: nil, notifiable: card, action: "due_soon")
      end
      card.update_column(:due_reminder_sent_at, Time.current)
    end
  end
end
