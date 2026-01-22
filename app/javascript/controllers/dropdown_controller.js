import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    // Bind the close method so we can remove the listener later
    this.close = this.close.bind(this)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation() // Stop click from immediately bubbling to window

    if (this.menuTarget.classList.contains("hidden")) {
      this.openMenu()
    } else {
      this.closeMenu()
    }
  }

  openMenu() {
    this.menuTarget.classList.remove("hidden")
    // Listen for clicks anywhere on the screen
    window.addEventListener("click", this.close)
  }

  closeMenu() {
    this.menuTarget.classList.add("hidden")
    // Stop listening to save memory
    window.removeEventListener("click", this.close)
  }

  close(event) {
    // If the click happened inside the dropdown, do nothing (keep it open)
    if (this.element.contains(event.target)) return

    // If click happened outside, close it
    this.closeMenu()
  }
}
