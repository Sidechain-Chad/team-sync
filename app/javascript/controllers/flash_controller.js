import { Controller } from "@hotwired/stimulus"

// Auto-dismiss flash messages. Click also dismisses immediately.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    this.element.addEventListener("click", () => this.dismiss())
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.classList.add("opacity-0", "transition-opacity", "duration-300")
    setTimeout(() => this.element.remove(), 300)
  }
}
