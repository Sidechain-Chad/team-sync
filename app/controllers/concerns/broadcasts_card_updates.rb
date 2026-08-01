# Re-broadcasts a card's board tile to everyone watching the board.
#
# Anything cards/_card renders — label pills, member avatars, cover image,
# attachment/comment counts, checklist progress — is visible to every viewer of
# the board, so a controller that changes one of those must push the fresh tile
# or the two viewers diverge. Three controllers had grown their own private copy
# of this method (card_labels, card_members, attachments); this is that method.
#
# `replace` targets by dom_id, so it is idempotent — but callers should still
# check their own response for a double render: if the actor's turbo_stream
# template also re-renders the tile, the actor gets two replacements. Every
# current caller responds with modal-internal frames only.
#
# Scope is the board tile only. Viewers with the card MODAL open do not see the
# modal's own sections change; that needs separate targets per section.
#
# Deliberately uniform: it takes no flags and no block. If a caller's
# associations are stale (e.g. AttachmentsController#destroy, where purge_later
# deletes the row but leaves the cached association), reload at the CALL SITE
# before calling this. That staleness is a fact about the caller, not about
# broadcasting, and baking it in here would make every other caller carry
# knowledge it doesn't need.
module BroadcastsCardUpdates
  extend ActiveSupport::Concern

  private

  def broadcast_card_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @card.list.board,
      target: @card,
      partial: "cards/card",
      locals: { card: @card }
    )
  end
end
