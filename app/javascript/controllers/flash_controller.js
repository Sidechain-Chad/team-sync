import { Controller } from "@hotwired/stimulus"

// Dismissal behaviour for a flash toast.
//
// The timeout value decides whether this toast is transient at all:
//
//   timeout > 0  -> auto-dismiss after that many ms (successes: 5000)
//   timeout <= 0 -> persist until the user dismisses it (errors)
//
// Errors persist because every error-surfacing path in the app funnels through
// this toast, and a message that removes itself after 5s is indistinguishable
// from a silent failure. Full reasoning in shared/_flash.html.erb.
//
// Click-anywhere-on-the-toast still dismisses (unchanged, and what the ✕ in
// shared/_flash_dismiss rides on). Deliberately no Esc binding: Esc already has
// three claimants — the card modal, the help overlay and the filter popover — and
// a fourth risks that chain.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    // A non-positive timeout means "no timer". Guarded rather than passed to
    // setTimeout, which would treat 0 as "next tick" and dismiss instantly.
    if (this.timeoutValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
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
