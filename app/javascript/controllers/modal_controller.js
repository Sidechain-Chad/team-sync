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
    this.element.addEventListener("turbo:frame-load", (event) => {
      // ONLY this frame's own load. turbo:frame-load BUBBLES, so every nested
      // frame inside the modal (the inline title editor, the description
      // editor, the due pill, the label rows) also reaches this listener — and
      // pulling focus onto the dialog after one of those loads is actively
      // destructive: the inline title editor autofocuses its field, so the
      // steal fired blur, and blur saves, closing the editor before a single
      // keystroke landed. The other nested frames had the same theft, just
      // without a blur handler to make it visible.
      if (event.target !== this.element) return

      if (this.hasDialogTarget) this.dialogTarget.focus()
    })
  }

  close() {
    // Remove the src attribute to empty the frame
    this.element.removeAttribute("src")
    this.element.innerHTML = ""
  }
}
