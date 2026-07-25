import { Controller } from "@hotwired/stimulus"

// Board-level keyboard shortcuts (Trello-style): a focus ring you move with
// the arrows, single-key actions on the focused card, plus global keys for
// search/filter/help. Every action dispatches by activating an EXISTING
// control (click a real link/button) rather than reimplementing behavior —
// see cards/_card.html.erb, lists/_list.html.erb, and boards/_filter_popover.
//
// Focus mechanism: real DOM focus. Each card's visible "surface" div (the
// one already carrying the focus-within:outline-brand-600 classes and the
// group-focus-within action-cluster reveal) gets tabindex="-1" in the ERB;
// navigating here just calls .focus() on that div, so the existing CSS
// paints the brand outline and reveals the hover actions for free — no new
// styles, no separate "focused card" state to keep in sync with the DOM.
export default class extends Controller {
  static targets = ["helpOverlay"]

  connect() {
    this.boundKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  keydown(event) {
    // Never hijack a modifier combo (Cmd/Ctrl/Alt) — those are the
    // browser's or OS's to handle (Cmd+F, Ctrl+N, etc.).
    if (event.metaKey || event.ctrlKey || event.altKey) return

    const typing = this.isTypingTarget(event.target)

    // Esc is the one shortcut that still applies while typing (closing the
    // help overlay / filter popover / card modal from inside a comment box
    // or the title edit is expected, not a hijack of the keystroke).
    if (event.key === "Escape") {
      this.handleEscape(event)
      return
    }

    if (typing) return // search box, comment field, title edit, tiptap description

    // Only Esc applies while the card modal is open (handled above) —
    // don't fight the modal, and don't let `?` stack the help overlay on
    // top of it either.
    if (this.modalOpen()) return

    // `?` must keep working while help is already open (that's how you
    // close it again), so check it before the "everything else is inert
    // while help is showing" gate below.
    if (event.key === "?") {
      event.preventDefault()
      this.toggleHelp()
      return
    }

    if (this.helpOpen()) return // arrows/n/c/f/search inert while help overlay is up

    switch (event.key) {
      case "/":
        event.preventDefault()
        this.focusSearch()
        break
      case "f":
        event.preventDefault()
        this.openFilter()
        break
      case "ArrowUp":
        event.preventDefault()
        this.moveFocus(-1, "vertical")
        break
      case "ArrowDown":
        event.preventDefault()
        this.moveFocus(1, "vertical")
        break
      case "ArrowLeft":
        event.preventDefault()
        this.moveFocus(-1, "horizontal")
        break
      case "ArrowRight":
        event.preventDefault()
        this.moveFocus(1, "horizontal")
        break
      case "Enter":
        this.openFocusedCard()
        break
      case "n":
        event.preventDefault()
        this.addCardInFocusedList()
        break
      case "c":
        event.preventDefault()
        this.archiveFocusedCard()
        break
    }
  }

  // ---- typing guard ----

  isTypingTarget(target) {
    if (!target || typeof target.closest !== "function") return false
    return !!target.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"]')
  }

  // ---- Esc: close the top-most thing ----

  handleEscape(event) {
    if (this.helpOpen()) {
      event.preventDefault()
      this.closeHelp()
    } else if (this.filterOpen()) {
      event.preventDefault()
      this.closeFilter()
    } else if (this.modalOpen()) {
      event.preventDefault()
      this.closeModal()
    }
  }

  // ---- help overlay (?) ----

  helpOpen() {
    return this.hasHelpOverlayTarget && !this.helpOverlayTarget.classList.contains("hidden")
  }

  toggleHelp() {
    if (this.helpOpen()) {
      this.closeHelp()
    } else {
      this.openHelp()
    }
  }

  openHelp() {
    if (!this.hasHelpOverlayTarget) return
    this.helpOverlayTarget.classList.remove("hidden")
    this.helpOverlayTarget.classList.add("flex")
  }

  closeHelp() {
    if (!this.hasHelpOverlayTarget) return
    this.helpOverlayTarget.classList.add("hidden")
    this.helpOverlayTarget.classList.remove("flex")
  }

  // Backdrop click closes, same convention as modal_controller.js — only
  // when the click landed on the backdrop itself, not the panel inside it.
  helpBackdropClick(event) {
    if (event.target === this.helpOverlayTarget) this.closeHelp()
  }

  // ---- filter popover (f) ----

  filterButton() {
    return document.querySelector('[aria-label="Filter cards"]')
  }

  filterMenu() {
    return this.filterButton()?.closest('[data-controller~="dropdown"]')?.querySelector('[data-dropdown-target="menu"]')
  }

  filterOpen() {
    const menu = this.filterMenu()
    return !!menu && !menu.classList.contains("hidden")
  }

  openFilter() {
    // The button's own click->dropdown#toggle handles open/close; since `f`
    // reuses that exact control, a second `f` naturally closes it again.
    this.filterButton()?.click()
  }

  closeFilter() {
    if (this.filterOpen()) this.filterButton()?.click()
  }

  // ---- search (/) ----

  focusSearch() {
    document.querySelector('input[aria-label="Search"]')?.focus()
  }

  // ---- card modal ----

  modalFrame() {
    return document.getElementById("modal")
  }

  modalOpen() {
    return !!this.modalFrame()?.querySelector('[data-modal-target="dialog"]')
  }

  // Clicks the modal's own invisible backdrop-overlay link (data-modal-exit
  // — see cards/show.html.erb), the same element a real backdrop click or
  // the ✕ button would activate, so this rides the exact same close path
  // (including any return-to/filter-preserving logic already wired to it).
  closeModal() {
    this.modalFrame()?.querySelector("[data-modal-exit]")?.click()
  }

  // ---- focused-card navigation ----

  focusedCardFrame() {
    return document.activeElement?.closest('turbo-frame[id^="card_"]') || null
  }

  cardSurface(frame) {
    return frame.querySelector("[data-filter-due]")
  }

  allLists() {
    return Array.from(this.element.querySelectorAll("[data-list-id]"))
  }

  // Cards currently visible in a list container, in DOM (visual) order —
  // filtered-out cards (board_filter_controller.js toggles "hidden" on the
  // surface div) are skipped so the ring never lands on an invisible card.
  visibleCardsIn(listEl) {
    return Array.from(listEl.querySelectorAll('turbo-frame[id^="card_"]')).filter((frame) => {
      const surface = this.cardSurface(frame)
      return !surface || !surface.classList.contains("hidden")
    })
  }

  focusCard(frame) {
    if (!frame) return
    this.cardSurface(frame)?.focus()
  }

  // Nothing focused yet — bootstrap onto the first visible card of the
  // first list, so arrows do something useful even before a card's ever
  // been clicked/tabbed to.
  focusFirstCard() {
    for (const list of this.allLists()) {
      const cards = this.visibleCardsIn(list)
      if (cards.length > 0) {
        this.focusCard(cards[0])
        return
      }
    }
  }

  moveFocus(delta, axis) {
    const current = this.focusedCardFrame()
    if (!current) {
      this.focusFirstCard()
      return
    }

    const currentList = current.closest("[data-list-id]")
    if (!currentList) return

    if (axis === "vertical") {
      const cards = this.visibleCardsIn(currentList)
      const index = cards.indexOf(current)
      const target = cards[index + delta]
      if (target) this.focusCard(target)
      return
    }

    // horizontal — move to the same row-index card in an adjacent list,
    // skipping any empty lists in that direction; stop at the boundary.
    const lists = this.allLists()
    const currentIndex = lists.indexOf(currentList)
    const rowIndex = this.visibleCardsIn(currentList).indexOf(current)

    for (let i = currentIndex + delta; i >= 0 && i < lists.length; i += delta) {
      const cards = this.visibleCardsIn(lists[i])
      if (cards.length > 0) {
        this.focusCard(cards[Math.min(rowIndex, cards.length - 1)])
        return
      }
    }
  }

  openFocusedCard() {
    const frame = this.focusedCardFrame()
    if (!frame) return
    frame.querySelector('a[data-turbo-frame="modal"]')?.click()
  }

  addCardInFocusedList() {
    const frame = this.focusedCardFrame()
    const listEl = frame?.closest("[data-list-id]")
    if (!listEl) return
    listEl.querySelector('turbo-frame[id$="_new_card"] a')?.click()
  }

  archiveFocusedCard() {
    const frame = this.focusedCardFrame()
    if (!frame) return
    frame.querySelector('[data-role="keyboard-archive"]')?.click()
  }
}
