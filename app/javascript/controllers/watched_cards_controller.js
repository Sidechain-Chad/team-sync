import { Controller } from "@hotwired/stimulus"

// Carries the current user's watched card ids for the board on screen (see
// boards/_watched_cards). Its only job is to re-apply badge visibility across the
// whole page whenever this element is (re)connected.
//
// That happens on the initial page load, and again every time
// CardsController#toggle_watch replaces #watched_cards — which is what makes the
// board behind the open modal light up (or go dark) the instant you toggle watch,
// with no board broadcast and therefore no chance of leaking one user's watch
// state to another viewer.
//
// The reverse direction — a tile being replaced while this element stays put — is
// handled by watch_badge_controller's own connect(), not from here.
export default class extends Controller {
  connect() {
    this.applyToAllBadges()
  }

  applyToAllBadges() {
    document.querySelectorAll('[data-controller~="watch-badge"]').forEach((el) => {
      // The badge may not have been initialised yet on first load; its own
      // connect() covers that case, so a miss here is fine rather than an error.
      this.application.getControllerForElementAndIdentifier(el, "watch-badge")?.apply()
    })
  }
}
