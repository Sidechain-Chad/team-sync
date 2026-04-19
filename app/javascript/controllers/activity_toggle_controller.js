import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "button"]

  toggle() {
    // Toggle the hidden class on the comments list
    this.listTarget.classList.toggle("hidden")

    // Update the button text
    if (this.listTarget.classList.contains("hidden")) {
      this.buttonTarget.textContent = "Show details"
    } else {
      this.buttonTarget.textContent = "Hide details"
    }
  }
}
