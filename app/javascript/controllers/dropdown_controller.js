import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const willOpen = this.menuTarget.classList.contains("hidden")

    if (willOpen) {
      this.closeOtherDropdowns()
      this.closeOpenDescriptionEditor()
    }

    this.menuTarget.classList.toggle("hidden")
  }

  // Used by inputs (e.g. the top-nav search) where calling toggle() would
  // preventDefault on the focus event and stop the input from focusing.
  // No preventDefault here, and no toggle behaviour — only opens. Closing
  // still happens via the document-level hide() listener.
  open() {
    if (!this.menuTarget.classList.contains("hidden")) return
    this.closeOtherDropdowns()
    this.closeOpenDescriptionEditor()
    this.menuTarget.classList.remove("hidden")
  }

  hide(event) {
    if (this.element.contains(event.target)) return
    this.menuTarget.classList.add("hidden")
  }

  closeOtherDropdowns() {
    document.querySelectorAll('[data-controller~="dropdown"]').forEach((el) => {
      if (el === this.element) return
      const menu = el.querySelector('[data-dropdown-target="menu"]')
      if (menu) menu.classList.add("hidden")
    })
  }

  // If the description is currently in edit mode, click its Cancel link
  // so the TipTap editor collapses back to read mode. Mirrors Trello —
  // opening a popover discards an in-progress description edit.
  closeOpenDescriptionEditor() {
    const editor = document.querySelector('[data-controller~="tiptap"]')
    if (!editor) return
    const cancelLink = editor.closest('turbo-frame')?.querySelector('a[href*="/cards/"]')
    if (cancelLink) cancelLink.click()
  }
}
