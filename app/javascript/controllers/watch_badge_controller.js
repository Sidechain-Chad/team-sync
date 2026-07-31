import { Controller } from "@hotwired/stimulus"

// The eye badge on a board tile, shown only when the CURRENT user watches that
// card.
//
// The badge is rendered by cards/_card.html.erb unconditionally and hidden, with
// no per-user state in the markup at all — that partial is broadcast to the board
// stream through ApplicationController.renderer, which has no session, so every
// viewer receives identical HTML and per-user state there would leak (or, reading
// a nil current_user, break every tile broadcast in the app). The per-user half
// lives in #watched_cards, rendered in request context.
//
// Visibility is therefore decided here, at connect. That timing is what makes the
// badge survive broadcasts: when a tile is replaced — a card edit, a label change,
// a full list replace from a drag — the new markup brings a NEW badge element,
// which connects and re-checks the set. No MutationObserver, no re-broadcast.
export default class extends Controller {
  static values = { cardId: Number }

  connect() {
    this.apply()
  }

  // Called on connect, and by watched_cards_controller for every badge on the
  // page whenever the set element itself is replaced.
  apply() {
    this.toggle(this.watchedIds().includes(this.cardIdValue))
  }

  toggle(watching) {
    // `hidden` off and `inline-flex` on — the badge's own classes are
    // `items-center gap-1`, which need a flex display to mean anything.
    this.element.classList.toggle("hidden", !watching)
    this.element.classList.toggle("inline-flex", watching)

    // A tile with no other badges renders its strip hidden and marked "empty"
    // (see cards/_card). Only that variant may be revealed — a "filled" strip is
    // already visible and must never be touched, or unwatching would hide a row
    // that still has a paperclip or a checklist count in it.
    const emptyStrip = this.element.closest('[data-watch-badge-strip="empty"]')
    if (emptyStrip) emptyStrip.classList.toggle("hidden", !watching)
  }

  watchedIds() {
    const source = document.getElementById("watched_cards")
    if (!source) return [] // no board page in view (e.g. the account Cards page)

    try {
      return JSON.parse(source.dataset.watchedCardIds || "[]")
    } catch {
      return []
    }
  }
}
