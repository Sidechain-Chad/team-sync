import { Controller } from "@hotwired/stimulus"

// Debounced search for the top-nav search input.
//
// On `input`, schedules a fetch to update the turbo-frame's src to
// /search?q=<value>. Turbo handles the actual request + DOM swap; this
// controller's only job is debouncing and URL construction.
//
// Debounce defaults to 200ms — feels snappy but coalesces typical typing
// into a single request per word.
export default class extends Controller {
  static targets = ["input", "frame"]
  static values  = { url: String, debounce: { type: Number, default: 200 } }

  query() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.fetch(), this.debounceValue)
  }

  fetch() {
    const q   = this.inputTarget.value.trim()
    const url = `${this.urlValue}?q=${encodeURIComponent(q)}`

    // Only update src if it actually changed — Turbo would refetch
    // on every assignment otherwise, even for identical URLs.
    if (this.frameTarget.src !== url) {
      this.frameTarget.src = url
    }
  }

  // Cancel any pending request when the controller is torn down (turbo
  // navigation away from the page, etc.) so we don't fire stale fetches.
  disconnect() {
    clearTimeout(this._timer)
  }
}
