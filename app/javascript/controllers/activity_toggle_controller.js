import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "button"]

  toggle() {
    this.itemTargets.forEach(item => {
      item.classList.toggle("hidden")
    })

    if (this.buttonTarget.textContent.includes("Hide")) {
      this.buttonTarget.textContent = "Show details"
    } else {
      this.buttonTarget.textContent = "Hide details"
    }
  }
}
