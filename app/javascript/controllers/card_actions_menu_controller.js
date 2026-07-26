import { Controller } from "@hotwired/stimulus"

// The card-actions (⋯) popover has two panels — the menu items (Copy/
// Archive) and the Copy-card form — that are never both visible at once.
// dropdown_controller.js owns whether the popover itself is open/closed;
// this controller only switches which panel shows inside it.
export default class extends Controller {
  static targets = ["menu", "form"]

  showCopyForm() {
    this.menuTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
  }

  showMenu() {
    this.formTarget.classList.add("hidden")
    this.menuTarget.classList.remove("hidden")
  }

  // Fired alongside dropdown#toggle on every ⋯ click. Only acts when that
  // toggle just opened the popover (its "menu" box no longer carries
  // "hidden"), so a previous "Copy card" session doesn't linger the next
  // time it's opened.
  reset() {
    const popover = this.element.querySelector('[data-dropdown-target="menu"]')
    if (!popover.classList.contains("hidden")) this.showMenu()
  }
}
