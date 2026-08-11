class DueSoonScanJob < ApplicationJob
  def perform
    # ALL THREE preloads exist because Card#subscribers reads members, card
    # watchers, AND (via card -> list -> board) the board's watchers. Dropping
    # any one of them issues a per-card query for that audience — an N+1 that
    # grows with the number of due cards. Pinned by a flat-lookup-query test in
    # DueSoonScanJobTest whose detection is proven by dropping each preload in
    # turn.
    #
    # `list: { board: :watchers }` is the board-watcher path: subscribers calls
    # `list.board.watchers`, so `list` and `board` must themselves be preloaded
    # too, not just the final `watchers` association — leaving either bare
    # still fires a per-card query even with `watchers` included on its own.
    Card.due_reminder_pending.includes(:members, :watchers, list: { board: :watchers }).find_each do |card|
      card.subscribers.each do |subscriber|
        Notification.deliver(recipient: subscriber, actor: nil, notifiable: card, action: "due_soon")
      end
      card.update_column(:due_reminder_sent_at, Time.current)
    end
  end
end
