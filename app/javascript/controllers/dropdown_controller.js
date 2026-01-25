import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle(event) {
    // Stop the click from bubbling up to the window immediately,
    // otherwise the 'click@window' action will catch it and close the menu instantly.
    event.preventDefault()
    event.stopPropagation()

    this.menuTarget.classList.toggle("hidden")
  }

  // Close if clicked outside (Triggered by data-action="click@window->dropdown#hide")
  hide(event) {
    // If the click is inside this dropdown wrapper, do nothing
    if (this.element.contains(event.target)) return

    // Otherwise, hide the menu
    this.menuTarget.classList.add("hidden")
  }
}
