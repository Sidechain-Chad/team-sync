import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    // Close when clicking the dark background
    this.element.addEventListener("click", (e) => {
      if (e.target === this.element) {
        this.close()
      }
    })

    // The frame element itself is only ever connected once (it lives in
    // the layout permanently); its content — including the dialog target —
    // is swapped in fresh each time a card opens. Move focus into the
    // dialog on every load rather than in connect(), which won't refire.
    this.element.addEventListener("turbo:frame-load", () => {
      if (this.hasDialogTarget) this.dialogTarget.focus()
    })
  }

  close() {
    // Remove the src attribute to empty the frame
    this.element.removeAttribute("src")
    this.element.innerHTML = ""
  }
}
